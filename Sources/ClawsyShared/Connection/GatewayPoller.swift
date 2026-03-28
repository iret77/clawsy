import Foundation
import Combine
import os.log

// MARK: - Gateway Poller

/// Fetches agents and sessions via Protocol V3 WebSocket requests.
/// All communication goes through the WebSocket — no REST needed.
public final class GatewayPoller: ObservableObject {

    @Published public var agents: [GatewayAgent] = []
    @Published public var sessions: [GatewaySession] = []
    @Published public var channels: [GatewayChannel] = []

    /// Where agent responses should go
    @Published public var responseChannel: ResponseChannel = .clawsy

    /// Currently targeted session key for routing events
    @Published public var targetSessionKey: String = "main" {
        didSet {
            SharedConfig.sharedDefaults.set(targetSessionKey, forKey: "targetSessionKey")
            SharedConfig.sharedDefaults.synchronize()
        }
    }

    private var timer: Timer?
    private let interval: TimeInterval
    private let logger = OSLog(subsystem: "ai.clawsy", category: "Poller")

    /// Pending response handlers keyed by request ID
    private var responseHandlers: [String: ([String: Any]) -> Void] = [:]

    /// Debug log callback — wired to ConnectionManager's rawLog
    public var onLog: ((String) -> Void)?

    /// Callback to send a Protocol V3 frame via the WebSocket
    public var onSendWebSocket: (([String: Any]) -> Void)?

    /// Callback to process incoming WS messages (check if they're responses to our requests)
    /// Returns true if the message was consumed.
    public func processMessage(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return false
        }

        // Handle responses to our requests (agent, status, chat.send)
        if type == "res", let id = json["id"] as? String {
            if let handler = responseHandlers.removeValue(forKey: id) {
                handler(json)
                return true
            }
            // chat.send response — extract the agent's reply from the res frame
            if let sessionKey = pendingChatRequests.removeValue(forKey: id) {
                handleChatResponse(json, sessionKey: sessionKey)
                return true
            }
        }

        // Handle gateway events — agent responses come as streaming events
        if type == "event" {
            if let event = json["event"] as? String {
                let handled = handleEvent(event, json: json)
                if !handled {
                    log("Unhandled event: \(event)")
                }
                return handled
            }
            // Event without event name — log the payload for debugging
            let payload = json["payload"] as? [String: Any]
            log("Event (no name): keys=\(payload?.keys.sorted() ?? [])")
            return true
        }

        // Log any other message types we don't handle
        if type != "res" {
            log("WS frame type=\(type)")
        }

        return false
    }

    /// Handle gateway events — detect agent responses to our messages.
    ///
    /// The gateway broadcasts chat events as:
    ///   { "type": "event", "event": "chat", "payload": { "state": "delta"|"final"|"aborted"|"error", "sessionKey": "...", "message": {...} } }
    private func handleEvent(_ event: String, json: [String: Any]) -> Bool {
        let payload = json["payload"] as? [String: Any]

        switch event {
        case "chat":
            // Primary chat event — streamed responses from the agent
            let sessionKey = payload?["sessionKey"] as? String ?? targetSessionKey
            guard let state = payload?["state"] as? String else {
                // Log all keys so we can see the actual format
                log("chat event keys: \(payload?.keys.sorted() ?? []) (no state)")
                return true
            }

            // Only show responses for our target session (QuickSend), not cron or other sessions
            let isRelevant = sessionKey.contains("main") || sessionKey == targetSessionKey
            if !isRelevant {
                // Silently ignore responses from cron jobs, other channels, etc.
                return true
            }

            log("chat.\(state) sessionKey=\(sessionKey)")

            switch state {
            case "delta":
                // Streaming chunk — extract text from message content
                let text = extractTextFromPayload(payload)
                if let text, !text.isEmpty {
                    accumulateResponseChunk(text, sessionKey: sessionKey)
                }

            case "final":
                // Final response — extract full text, or emit accumulated chunks
                let text = extractTextFromPayload(payload)
                if let text, !text.isEmpty {
                    // Final has the complete message — use it directly
                    let agentName = agents.first { sessionKey.contains($0.id) }?.name ?? "Agent"
                    log("Chat final from \(agentName): \(text.prefix(80))…")
                    // Clear any accumulated chunks (final is authoritative)
                    accumulatedResponses.removeValue(forKey: sessionKey)
                    DispatchQueue.main.async { [weak self] in
                        self?.onAgentResponse?(agentName, text, sessionKey)
                    }
                } else {
                    // No text in final — emit whatever was accumulated from deltas
                    emitAccumulatedResponse(sessionKey: sessionKey)
                }

            case "aborted":
                // User interrupted — emit what we have so far
                emitAccumulatedResponse(sessionKey: sessionKey)

            case "error":
                let errorMsg = payload?["errorMessage"] as? String ?? "Unknown error"
                log("Chat error: \(errorMsg)")
                accumulatedResponses.removeValue(forKey: sessionKey)

            default:
                log("Chat unknown state: \(state)")
            }
            return true

        case "chat.chunk":
            // Legacy format — some gateways may still use this
            if let text = payload?["text"] as? String,
               let sessionKey = payload?["sessionKey"] as? String {
                accumulateResponseChunk(text, sessionKey: sessionKey)
            }
            return true

        case "chat.done", "session.done":
            // Legacy format
            if let sessionKey = payload?["sessionKey"] as? String ?? payload?["key"] as? String {
                emitAccumulatedResponse(sessionKey: sessionKey)
            }
            return true

        case "tick", "agent", "health", "status", "presence", "cron":
            // Known gateway events — no action needed
            return true

        default:
            return false
        }
    }

    /// Extract text from the ENTIRE payload dict — searches all known locations.
    /// The gateway chat event payload may have text in various places:
    ///   payload.message.content[].text (Anthropic content blocks)
    ///   payload.message.text
    ///   payload.message (direct string)
    ///   payload.text
    ///   payload.content
    ///   payload.response
    private func extractTextFromPayload(_ payload: [String: Any]?) -> String? {
        guard let payload else { return nil }

        // Try payload.message first (most common)
        if let result = extractTextFromMessage(payload["message"]) {
            return result
        }
        // Try direct payload fields
        if let text = payload["text"] as? String, !text.isEmpty { return text }
        if let text = payload["response"] as? String, !text.isEmpty { return text }
        if let text = payload["content"] as? String, !text.isEmpty { return text }

        // Try payload.result.message (nested)
        if let result = payload["result"] as? [String: Any] {
            if let text = extractTextFromMessage(result["message"]) { return text }
            if let text = result["text"] as? String, !text.isEmpty { return text }
        }

        return nil
    }

    /// Extract text content from a message object.
    /// Messages can be plain strings, dicts with text/content, or content blocks.
    private func extractTextFromMessage(_ message: Any?) -> String? {
        // Direct string
        if let text = message as? String, !text.isEmpty {
            return text
        }

        // Message dict with "text" or "content" field
        if let msgDict = message as? [String: Any] {
            if let text = msgDict["text"] as? String, !text.isEmpty {
                return text
            }
            // Content blocks: [{ "type": "text", "text": "..." }]
            if let content = msgDict["content"] as? [[String: Any]] {
                let texts = content.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }
                let joined = texts.joined(separator: "\n")
                return joined.isEmpty ? nil : joined
            }
            if let content = msgDict["content"] as? String, !content.isEmpty {
                return content
            }
        }

        return nil
    }

    // MARK: - Chat Response Handling

    /// Extract the agent's reply from a chat.send res frame.
    /// The gateway may return the response in several formats:
    ///   1. payload.message (plain text response)
    ///   2. payload.text (alternative text field)
    ///   3. payload.content (structured response)
    ///   4. payload.response (wrapped response)
    ///   5. Direct result in payload as string
    private func handleChatResponse(_ json: [String: Any], sessionKey: String) {
        let payload = json["payload"] as? [String: Any]

        // Try all known response formats
        let responseText: String? =
            payload?["message"] as? String ??
            payload?["text"] as? String ??
            payload?["response"] as? String ??
            payload?["content"] as? String ??
            (payload?["result"] as? [String: Any])?["message"] as? String ??
            (payload?["result"] as? [String: Any])?["text"] as? String ??
            json["message"] as? String ??
            json["text"] as? String

        if let text = responseText, !text.isEmpty {
            let agentName = agents.first { agent in
                sessionKey.contains(agent.id)
            }?.name ?? "Agent"

            log("chat.send response from \(agentName): \(text.prefix(80))…")

            DispatchQueue.main.async { [weak self] in
                self?.onAgentResponse?(agentName, text, sessionKey)
            }
        } else {
            // Log the raw response for debugging
            log("chat.send response (no text extracted): \(String(describing: payload?.keys.sorted()))")

            // Even without text, check if there were accumulated streaming chunks
            emitAccumulatedResponse(sessionKey: sessionKey)
        }
    }

    // MARK: - Response Accumulation

    private var accumulatedResponses: [String: String] = [:]

    private func accumulateResponseChunk(_ text: String, sessionKey: String) {
        accumulatedResponses[sessionKey, default: ""] += text
    }

    private func emitAccumulatedResponse(sessionKey: String) {
        guard let responseText = accumulatedResponses.removeValue(forKey: sessionKey),
              !responseText.isEmpty else { return }

        // Find the agent name for this session
        let agentName = agents.first { agent in
            sessionKey.contains(agent.id)
        }?.name ?? "Agent"

        log("Response from \(agentName): \(responseText.prefix(60))…")

        DispatchQueue.main.async { [weak self] in
            self?.onAgentResponse?(agentName, responseText, sessionKey)
        }
    }

    public init(interval: TimeInterval = 30) {
        self.interval = interval
        self.targetSessionKey = SharedConfig.sharedDefaults.string(forKey: "targetSessionKey") ?? "main"
    }

    /// Start periodic polling.
    public func start() {
        stop()
        log("Poller started (interval: \(Int(interval))s)")
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Stop polling.
    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stop() }

    // MARK: - WebSocket Requests

    private func sendRequest(method: String, params: [String: Any] = [:], handler: @escaping ([String: Any]) -> Void) {
        let id = UUID().uuidString
        responseHandlers[id] = handler

        var frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": method
        ]
        if !params.isEmpty {
            frame["params"] = params
        }

        guard let sender = onSendWebSocket else {
            log("ERROR: onSendWebSocket not wired — \(method) dropped!")
            responseHandlers.removeValue(forKey: id)
            return
        }
        sender(frame)

        // Timeout: clean up handler after 15s if no response
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            if self?.responseHandlers.removeValue(forKey: id) != nil {
                self?.log("\(method) timed out")
            }
        }
    }

    // MARK: - Polling

    private func poll() {
        fetchAgents()
        fetchSessions()
        fetchChannels()
    }

    private func fetchAgents() {
        // Gateway Protocol V3: "agents.list" returns { defaultId, mainKey, scope, agents: [{ id, name?, identity? }] }
        sendRequest(method: "agents.list") { [weak self] response in
            guard let payload = response["payload"] as? [String: Any] else {
                self?.log("agents.list: no payload (keys: \(response.keys.sorted()))")
                return
            }
            self?.log("agents.list response keys: \(payload.keys.sorted())")
            self?.parseAgents(payload)
        }
    }

    private func parseAgents(_ payload: [String: Any]) {
        var parsed: [GatewayAgent] = []

        // Official format: { agents: [{ id, name?, identity?: { name?, emoji?, avatar?, avatarUrl? } }] }
        if let agentsList = payload["agents"] as? [[String: Any]] {
            for a in agentsList {
                if let id = a["id"] as? String {
                    // Prefer identity.name > name > id
                    let identity = a["identity"] as? [String: Any]
                    let name = identity?["name"] as? String
                        ?? a["name"] as? String
                        ?? id
                    parsed.append(GatewayAgent(id: id, name: name))
                }
            }
        }

        if !parsed.isEmpty {
            // Store defaultId for session routing
            let defaultId = payload["defaultId"] as? String
            DispatchQueue.main.async {
                self.agents = parsed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.log("Agents (\(parsed.count)): \(parsed.map { $0.name }.joined(separator: ", "))")
                // If no target session key is persisted, use the default agent
                if let defaultId, self.targetSessionKey == "main" || self.targetSessionKey.isEmpty {
                    self.targetSessionKey = defaultId
                }
            }
        } else {
            log("parseAgents: no agents found in keys \(payload.keys.sorted())")
        }
    }

    private func fetchSessions() {
        sendRequest(method: "status") { [weak self] response in
            guard let payload = response["payload"] as? [String: Any] else { return }

            // "status" returns presence info with sessions
            guard let sessions = payload["sessions"] as? [[String: Any]] else {
                // Try "presence" sub-object
                if let presence = payload["presence"] as? [[String: Any]] {
                    self?.parseSessions(presence)
                }
                return
            }
            self?.parseSessions(sessions)
        }
    }

    private func parseSessions(_ sessionsList: [[String: Any]]) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let parsed: [GatewaySession] = sessionsList.compactMap { s in
            guard let key = s["key"] as? String ?? s["sessionKey"] as? String else { return nil }
            let startedAt: Date? = (s["startedAt"] as? String).flatMap { isoFormatter.date(from: $0) }
            return GatewaySession(
                id: key,
                label: s["label"] as? String,
                kind: s["kind"] as? String ?? "unknown",
                status: s["status"] as? String ?? "unknown",
                model: s["model"] as? String,
                startedAt: startedAt,
                task: s["task"] as? String
            )
        }

        DispatchQueue.main.async {
            self.sessions = parsed
        }
    }

    private func fetchChannels() {
        sendRequest(method: "channels.status") { [weak self] response in
            guard let payload = response["payload"] as? [String: Any],
                  let channelsList = payload["channels"] as? [[String: Any]] else {
                // channels.status might not be available — not critical
                return
            }

            let parsed: [GatewayChannel] = channelsList.compactMap { c -> GatewayChannel? in
                let id = (c["type"] as? String) ?? (c["id"] as? String)
                guard let id else { return nil }
                let name = (c["name"] as? String) ?? (c["label"] as? String) ?? id.capitalized
                let connected = (c["connected"] as? Bool) ?? ((c["status"] as? String) == "connected")
                return GatewayChannel(id: id, name: name, isConnected: connected)
            }

            DispatchQueue.main.async {
                self?.channels = parsed.filter { $0.isConnected }
            }
        }
    }

    // MARK: - Send: Chat Messages (QuickSend)

    /// Send a plain text message to an agent session via Protocol V3 `chat.send`.
    /// Used ONLY for QuickSend — user-initiated chat messages.
    /// `deliver: true` triggers agent processing and response generation.
    public func sendChatMessage(_ message: String, sessionKey: String) {
        let requestId = UUID().uuidString
        let frame: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.send",
            "params": [
                "sessionKey": sessionKey,
                "message": message,
                "deliver": true,
                "idempotencyKey": UUID().uuidString
            ]
        ]

        // Track this request so we can match the response
        pendingChatRequests[requestId] = sessionKey

        log("chat.send → \(sessionKey) (\(message.prefix(60))…)")
        send(frame)
    }

    /// Pending chat.send requests awaiting responses
    private var pendingChatRequests: [String: String] = [:]

    /// Callback when an agent response is received for a chat.send
    public var onAgentResponse: ((_ agentName: String, _ message: String, _ sessionKey: String) -> Void)?

    // MARK: - Send: Node Events (Screenshot, Clipboard, Camera, Share)

    /// Send a node event via Protocol V3 `node.event`.
    /// Used for ambient context: screenshots, clipboard, camera, share, file rules.
    /// This is the correct Protocol V3 mechanism for node-to-gateway events.
    public func sendNodeEvent(event: String, payload: [String: Any]? = nil) {
        var params: [String: Any] = [
            "event": event,
            "sessionKey": targetSessionKey
        ]
        if let payload = payload {
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                params["payloadJSON"] = jsonString
            }
        }

        let frame: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "node.event",
            "params": params
        ]

        log("node.event → \(event) → \(targetSessionKey)")
        send(frame)
    }

    /// Send a clawsy_envelope as a node event.
    /// Wraps the envelope type and content into a structured node event.
    public func sendEnvelope(type: String, content: Any, metadata: [String: Any] = [:]) {
        var payload: [String: Any] = [
            "type": type,
            "version": SharedConfig.shortVersion,
            "localTime": ISO8601DateFormatter().string(from: Date()),
            "tz": TimeZone.current.identifier,
            "content": content
        ]
        metadata.forEach { payload[$0.key] = $0.value }

        sendNodeEvent(event: "clawsy.\(type)", payload: payload)
    }

    // MARK: - Internal Send

    private func send(_ frame: [String: Any]) {
        guard let sender = onSendWebSocket else {
            log("ERROR: onSendWebSocket not wired — frame dropped!")
            return
        }
        sender(frame)
    }

    // MARK: - Logging

    private func log(_ message: String) {
        os_log("[Poller] %{public}@", log: logger, type: .info, message)
        onLog?("[POLLER] \(message)")
    }
}
