import Foundation
import Combine
import os.log

// MARK: - Node Connection Manager

/// Manages a second WebSocket connection with `role: "node"` to register
/// this device in the gateway's NodeRegistry, enabling Shared Folder access
/// via `nodes invoke` commands.
///
/// This is a lightweight companion to the main `ConnectionManager` (operator).
/// It does NOT manage SSH tunnels or retries independently — it piggybacks
/// on the operator connection's tunnel and lifecycle.
public final class NodeConnectionManager: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var isConnected: Bool = false

    // MARK: - Components

    public let transport = WebSocketTransport()
    public let commandRouter = CommandRouter()

    private var handshake: HandshakeManager?
    private var shouldBeConnected = false
    private var reconnectTimer: Timer?
    private var reconnectAttempt = 0

    private let logger = OSLog(subsystem: "ai.clawsy", category: "NodeConnection")

    // MARK: - Callbacks

    /// Log messages are forwarded to the operator's rawLog
    public var onLog: ((String) -> Void)?

    /// Called when command handlers need to be registered on this router
    public var onRegisterHandlers: ((CommandRouter) -> Void)?

    // MARK: - Constants

    private static let maxReconnectDelay: TimeInterval = 30
    private static let baseReconnectDelay: TimeInterval = 2

    // MARK: - Init

    public init() {
        wireTransport()
        wireCommandRouter()
    }

    // MARK: - Public API

    /// Start the node connection to the given WebSocket URL.
    /// Uses its own HandshakeManager with `role: "node"`.
    public func connect(url: URL, gatewayToken: String, deviceToken: String?, origin: String? = nil) {
        shouldBeConnected = true
        reconnectAttempt = 0

        log("Connecting node WebSocket to \(url.absoluteString)")

        // Build node-specific handshake config
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let deviceName = Host.current().localizedName ?? "Mac"

        let hsConfig = HandshakeManager.Config(
            gatewayToken: gatewayToken,
            deviceToken: deviceToken,
            capabilities: [],
            commands: [
                "file.list", "file.get", "file.set", "file.mkdir",
                "file.delete", "file.move", "file.copy", "file.rename",
                "file.get.chunk", "file.set.chunk",
                "file.stat", "file.exists", "file.rmdir",
                "file.batch", "file.checksum"
            ],
            permissions: [
                "file.read": true,
                "file.write": true
            ],
            role: "node",
            scopes: [],
            displayName: "Clawsy Node (\(deviceName))"
        )

        let hs = HandshakeManager(config: hsConfig)
        self.handshake = hs
        wireHandshake(hs)

        // Register file command handlers
        onRegisterHandlers?(commandRouter)

        // Open WebSocket
        transport.connect(to: url, timeout: 12.0, origin: origin)
    }

    /// Disconnect the node connection. Stops reconnect attempts.
    public func disconnect() {
        shouldBeConnected = false
        stopReconnectTimer()
        handshake = nil
        transport.disconnect()
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
        }
        log("Node connection disconnected")
    }

    // MARK: - Wiring

    private func wireTransport() {
        transport.onConnected = { [weak self] in
            self?.log("Node WebSocket connected, starting handshake")
        }

        transport.onDisconnected = { [weak self] code, reason in
            guard let self = self else { return }
            self.log("Node WebSocket disconnected: \(code) \(reason)")
            DispatchQueue.main.async {
                self.isConnected = false
            }
            self.scheduleReconnectIfNeeded()
        }

        transport.onError = { [weak self] error in
            guard let self = self else { return }
            self.log("Node WebSocket error: \(error)")
            DispatchQueue.main.async {
                self.isConnected = false
            }
            self.scheduleReconnectIfNeeded()
        }

        transport.onMessage = { [weak self] text in
            guard let self = self else { return }

            // Try handshake first
            if self.handshake?.processMessage(text) == true { return }

            // Then command router (node.invoke.request)
            self.commandRouter.processMessage(text)
        }
    }

    private func wireHandshake(_ hs: HandshakeManager) {
        hs.onSendMessage = { [weak self] message in
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let text = String(data: data, encoding: .utf8) else { return }
            self?.transport.send(text)
        }

        hs.onHandshakeComplete = { [weak self] result in
            guard let self = self else { return }
            self.log("Node handshake complete (connId: \(result.connId ?? "n/a"))")
            self.reconnectAttempt = 0
            DispatchQueue.main.async {
                self.isConnected = true
            }
        }

        hs.onHandshakeFailed = { [weak self] reason in
            self?.log("Node handshake failed: \(reason)")
            self?.transport.disconnect()
            self?.scheduleReconnectIfNeeded()
        }

        hs.onPairingRequired = { [weak self] _ in
            // Node connection shouldn't need pairing if operator is already paired.
            // If it does, log and skip — the operator handles pairing.
            self?.log("Node connection pairing requested (unexpected)")
        }
    }

    private func wireCommandRouter() {
        commandRouter.onSendMessage = { [weak self] message in
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let text = String(data: data, encoding: .utf8) else { return }
            self?.transport.send(text)
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnectIfNeeded() {
        guard shouldBeConnected else { return }
        stopReconnectTimer()

        reconnectAttempt += 1
        let delay = min(
            Self.baseReconnectDelay * pow(2.0, Double(reconnectAttempt - 1)),
            Self.maxReconnectDelay
        )

        log("Node reconnect in \(Int(delay))s (attempt \(reconnectAttempt))")

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, self.shouldBeConnected else { return }
            self.log("Node reconnecting...")
            // Re-open the transport to the same URL — handshake will re-run
            // The connect() call needs to be made by HostManager since it knows the URL
            self.onReconnectNeeded?()
        }
    }

    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    /// Called when the node connection needs to reconnect.
    /// HostManager sets this to re-call connect() with the correct URL.
    public var onReconnectNeeded: (() -> Void)?

    // MARK: - Logging

    private func log(_ message: String) {
        os_log("[NodeConn] %{public}@", log: logger, type: .info, message)
        onLog?("[NODE] \(message)")
    }
}
