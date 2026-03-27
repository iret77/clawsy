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
        if type == "event", let event = json["event"] as? String {
            return handleEvent(event, json: json)
        }

        return false
    }

    /// Handle gateway events — detect agent responses to our messages.
    private func handleEvent(_ event: String, json: [String: Any]) -> Bool {
        let payload = json["payload"] as? [String: Any]

        switch event {
        case "chat.chunk":
            // Streaming response chunk — accumulate for final response
            if let text = payload?["text"] as? String,
               let sessionKey = payload?["sessionKey"] as? String {
                accumulateResponseChunk(text, sessionKey: sessionKey)
            }
            return true

        case "chat.done", "session.done":
            // Agent finished responding — emit accumulated response
            if let sessionKey = payload?["sessionKey"] as? String ?? payload?["key"] as? String {
                emitAccumulatedResponse(sessionKey: sessionKey)
            }
            return true

        case "tick":
            // Gateway keepalive — ignore
            return true

        default:
            return false
        }
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
        sendRequest(method: "agent") { [weak self] response in
            guard let payload = response["payload"] as? [String: Any] else {
                // Try direct response format
                if let ok = response["ok"] as? Bool, ok,
                   let payload = response["payload"] as? [String: Any] {
                    self?.parseAgents(payload)
                }
                return
            }
            self?.parseAgents(payload)
        }
    }

    private func parseAgents(_ payload: [String: Any]) {
        // The "agent" method returns agent config — extract agents from it
        var parsed: [GatewayAgent] = []

        // Try "agents" array format
        if let agentsList = payload["agents"] as? [[String: Any]] {
            for a in agentsList {
                if let id = a["id"] as? String, let name = a["name"] as? String {
                    parsed.append(GatewayAgent(id: id, name: name))
                }
            }
        }
        // Try single agent format (the "agent" method might return current agent info)
        else if let id = payload["id"] as? String, let name = payload["name"] as? String {
            parsed.append(GatewayAgent(id: id, name: name))
        }
        // Try "config" sub-object
        else if let config = payload["config"] as? [String: Any],
                let agents = config["agents"] as? [String: [String: Any]] {
            for (id, info) in agents {
                let name = info["name"] as? String ?? id
                parsed.append(GatewayAgent(id: id, name: name))
            }
        }

        if !parsed.isEmpty {
            DispatchQueue.main.async {
                self.agents = parsed.sorted { $0.name < $1.name }
                self.log("Agents: \(parsed.map { $0.name }.joined(separator: ", "))")
            }
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
        var params: [String: Any] = ["event": event]
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

        log("node.event → \(event)")
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
