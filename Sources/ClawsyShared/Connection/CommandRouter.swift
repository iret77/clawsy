import Foundation
import os.log

// MARK: - Command Router

/// Routes incoming `node.invoke.request` events to registered handlers.
/// Handles timeout, response formatting, and error reporting.
///
/// Protocol V3 flow:
/// 1. Gateway sends `node.invoke.request` event
/// 2. Router finds handler for the command
/// 3. Handler executes and returns result
/// 4. Router sends `node.invoke.result` response
public final class CommandRouter {

    // MARK: - Types

    /// Result of a command execution
    public enum CommandResult {
        case success([String: Any])
        case error(code: String, message: String)
    }

    /// A command handler function
    public typealias CommandHandler = (
        _ params: [String: Any],
        _ completion: @escaping (CommandResult) -> Void
    ) -> Void

    /// A synchronous command handler (for simple operations)
    public typealias SyncCommandHandler = (
        _ params: [String: Any]
    ) -> CommandResult

    // MARK: - Properties

    private var handlers: [String: CommandHandler] = [:]
    private let logger = OSLog(subsystem: "ai.clawsy", category: "CommandRouter")

    /// Callback to send a JSON message over the WebSocket.
    public var onSendMessage: (([String: Any]) -> Void)?

    /// Callback when a command requires user approval.
    /// Returns true if approved, false if denied.
    public var onApprovalRequired: ((
        _ command: String,
        _ params: [String: Any],
        _ completion: @escaping (Bool) -> Void
    ) -> Void)?

    /// Commands that always require user approval via the onApprovalRequired callback.
    /// Note: screen.capture and clipboard.read have their own dialogs in their handlers,
    /// so they don't need this layer. camera.snap requires macOS Camera permission.
    public var approvalRequiredCommands: Set<String> = []

    /// Commands that never require approval (within sandbox)
    public var autoApprovedCommands: Set<String> = [
        "file.list", "file.get", "file.set", "file.mkdir",
        "file.delete", "file.move", "file.copy", "file.rename",
        "file.get.chunk", "file.set.chunk",
        "file.stat", "file.exists", "file.rmdir",
        "file.batch", "file.checksum",
        "clipboard.write",
        "location.get"
    ]

    // MARK: - Registration

    /// Register an async command handler
    public func register(_ command: String, handler: @escaping CommandHandler) {
        handlers[command] = handler
    }

    /// Register a synchronous command handler (convenience)
    public func registerSync(_ command: String, handler: @escaping SyncCommandHandler) {
        handlers[command] = { params, completion in
            let result = handler(params)
            completion(result)
        }
    }

    /// Unregister a command handler
    public func unregister(_ command: String) {
        handlers.removeValue(forKey: command)
    }

    /// List all registered commands
    public var registeredCommands: [String] {
        Array(handlers.keys).sorted()
    }

    // MARK: - Message Processing

    /// Process an incoming WebSocket message. Returns true if it was a node.invoke.request.
    @discardableResult
    public func processMessage(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        guard let type = json["type"] as? String else { return false }

        // Handle node.invoke.request events
        if type == "event",
           let event = json["event"] as? String,
           event == "node.invoke.request",
           let payload = json["payload"] as? [String: Any] {
            handleInvokeRequest(payload)
            return true
        }

        return false
    }

    // MARK: - Invoke Handling

    private func handleInvokeRequest(_ payload: [String: Any]) {
        guard let invokeId = payload["id"] as? String,
              let nodeId = payload["nodeId"] as? String,
              let command = payload["command"] as? String else {
            os_log("[Router] Invalid invoke request: missing id/nodeId/command", log: logger, type: .error)
            return
        }

        let timeoutMs = payload["timeoutMs"] as? Int ?? 30000

        // Parse params from JSON string
        var params: [String: Any] = [:]
        if let paramsJSON = payload["paramsJSON"] as? String,
           let paramsData = paramsJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any] {
            params = parsed
        } else if let directParams = payload["params"] as? [String: Any] {
            // Some gateways send params directly
            params = directParams
        }

        os_log("[Router] Invoke: %{public}@ (id: %{public}@, timeout: %{public}dms)",
               log: logger, command, invokeId.prefix(8) + "...", timeoutMs)

        // Check if handler exists
        guard let handler = handlers[command] else {
            os_log("[Router] No handler for command: %{public}@", log: logger, type: .error, command)
            sendInvokeResult(invokeId: invokeId, nodeId: nodeId,
                           result: .error(code: "unknown_command", message: "No handler for '\(command)'"))
            return
        }

        // Guard against double-fire (timeout vs handler completion race)
        let responseLock = NSLock()
        var hasResponded = false

        // Set up timeout
        let timeoutWork = DispatchWorkItem { [weak self] in
            responseLock.lock()
            guard !hasResponded else { responseLock.unlock(); return }
            hasResponded = true
            responseLock.unlock()

            os_log("[Router] Timeout for %{public}@ (id: %{public}@)", log: self?.logger ?? .default, type: .error, command, invokeId.prefix(8) + "...")
            self?.sendInvokeResult(invokeId: invokeId, nodeId: nodeId,
                                  result: .error(code: "timeout", message: "Command timed out after \(timeoutMs)ms"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timeoutWork)

        // Check approval
        let needsApproval = approvalRequiredCommands.contains(command)
            && !autoApprovedCommands.contains(command)

        let executeHandler = { [weak self] in
            handler(params) { [weak self] result in
                responseLock.lock()
                guard !hasResponded else { responseLock.unlock(); return }
                hasResponded = true
                responseLock.unlock()

                timeoutWork.cancel()
                self?.sendInvokeResult(invokeId: invokeId, nodeId: nodeId, result: result)
            }
        }

        if needsApproval, let approvalHandler = onApprovalRequired {
            approvalHandler(command, params) { [weak self] approved in
                if approved {
                    executeHandler()
                } else {
                    responseLock.lock()
                    guard !hasResponded else { responseLock.unlock(); return }
                    hasResponded = true
                    responseLock.unlock()

                    timeoutWork.cancel()
                    self?.sendInvokeResult(invokeId: invokeId, nodeId: nodeId,
                                           result: .error(code: "denied", message: "User denied '\(command)'"))
                }
            }
        } else {
            executeHandler()
        }
    }

    // MARK: - Response

    private func sendInvokeResult(invokeId: String, nodeId: String, result: CommandResult) {
        var params: [String: Any] = [
            "id": invokeId,
            "nodeId": nodeId
        ]

        switch result {
        case .success(let payload):
            params["ok"] = true
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                params["payloadJSON"] = jsonString
            }

        case .error(let code, let message):
            params["ok"] = false
            params["error"] = ["code": code, "message": message]
        }

        let message: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "node.invoke.result",
            "params": params
        ]

        os_log("[Router] Sending result for %{public}@ (ok: %{public}@)",
               log: logger, invokeId.prefix(8) + "...", result.isOk ? "true" : "false")

        DispatchQueue.main.async { [weak self] in
            self?.onSendMessage?(message)
        }
    }
}

// MARK: - CommandResult Extension

extension CommandRouter.CommandResult {
    var isOk: Bool {
        if case .success = self { return true }
        return false
    }
}
