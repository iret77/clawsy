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
            // Reset inbox state when agent changes so it re-provisions
            clawsyInboxReady = false
            memoryMdUpdated = false
        }
    }

    // MARK: - Clawsy Inbox

    /// Session key for the clawsy-inbox (derived from agent ID in targetSessionKey)
    public var clawsyInboxSessionKey: String {
        if let agentId = currentAgentId {
            return "agent:\(agentId):clawsy-inbox"
        }
        return "clawsy-inbox"
    }

    /// Extract agent ID from targetSessionKey (format: "agent:<id>:main")
    public var currentAgentId: String? {
        let parts = targetSessionKey.split(separator: ":")
        return parts.count >= 2 ? String(parts[1]) : nil
    }

    /// Agent display name for the currently targeted agent
    public var currentAgentName: String {
        if let agentId = currentAgentId {
            return agents.first { $0.id == agentId }?.name ?? agentId
        }
        return "Agent"
    }

    private var clawsyInboxReady = false
    private var memoryMdUpdated = false

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
        clawsyInboxReady = false
        memoryMdUpdated = false
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
            let defaultId = payload["defaultId"] as? String
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.agents = parsed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.log("Agents (\(parsed.count)): \(parsed.map { $0.name }.joined(separator: ", "))")
                // Auto-select default agent only on first launch (no user selection persisted yet)
                if let defaultId, self.targetSessionKey == "main" || self.targetSessionKey.isEmpty {
                    self.targetSessionKey = "agent:\(defaultId):main"
                    self.log("Auto-selected default agent: \(defaultId)")
                }
            }
        } else {
            log("parseAgents: no agents found in keys \(payload.keys.sorted())")
        }
    }

    private func fetchSessions() {
        // Protocol V3: sessions.list returns { sessions: [{ key, displayName?, provider?, subject?, ... }] }
        sendRequest(method: "sessions.list", params: [
            "activeMinutes": 60,
            "includeGlobal": true
        ]) { [weak self] response in
            guard let payload = response["payload"] as? [String: Any],
                  let sessions = payload["sessions"] as? [[String: Any]] else {
                self?.log("sessions.list: no sessions in payload")
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
            let startedAt: Date? = (s["startedAt"] as? String ?? s["createdAt"] as? String)
                .flatMap { isoFormatter.date(from: $0) }
            return GatewaySession(
                id: key,
                label: s["displayName"] as? String ?? s["label"] as? String,
                kind: s["kind"] as? String ?? "unknown",
                status: s["status"] as? String ?? "unknown",
                model: s["model"] as? String ?? s["provider"] as? String,
                startedAt: startedAt,
                task: s["subject"] as? String ?? s["task"] as? String
            )
        }

        DispatchQueue.main.async { [weak self] in
            self?.sessions = parsed
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
    /// Used for QuickSend — user-initiated chat messages.
    /// `deliver: true` triggers agent processing and response generation.
    public func sendChatMessage(_ message: String, sessionKey: String, deliver: Bool = true, attachments: [[String: Any]]? = nil) {
        let requestId = UUID().uuidString
        var params: [String: Any] = [
            "sessionKey": sessionKey,
            "message": message,
            "deliver": deliver,
            "idempotencyKey": UUID().uuidString
        ]
        if let attachments = attachments {
            params["attachments"] = attachments
        }

        let frame: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.send",
            "params": params
        ]

        // Only track requests where we want to show the response as a toast.
        // Inbox messages are context-only — the agent's memory.md instructs it to reply
        // with just "ok", so token waste is minimal. No toast needed for inbox responses.
        if !sessionKey.contains("clawsy-inbox") {
            pendingChatRequests[requestId] = sessionKey
        }

        log("chat.send → \(sessionKey) (\(message.prefix(60))…)")
        send(frame)
    }

    /// Pending chat.send requests awaiting responses
    private var pendingChatRequests: [String: String] = [:]

    /// Callback when an agent response is received for a chat.send
    public var onAgentResponse: ((_ agentName: String, _ message: String, _ sessionKey: String) -> Void)?

    // MARK: - Clawsy Inbox Setup

    /// Ensure the clawsy-inbox session exists for the target agent.
    /// Creates it via `sessions.create` once per connection/agent-switch.
    public func ensureClawsyInbox(completion: (() -> Void)? = nil) {
        guard !clawsyInboxReady else { completion?(); return }
        let sessionKey = clawsyInboxSessionKey
        sendRequest(method: "sessions.create", params: [
            "key": sessionKey,
            "label": "Clawsy Inbox"
        ]) { [weak self] response in
            // Session may already exist — both cases are fine
            self?.clawsyInboxReady = true
            self?.log("clawsy-inbox ready: \(sessionKey)")
            self?.ensureMemoryMdUpdated()
            completion?()
        }
    }

    /// Block version — bump this when the clawsy memory block content changes.
    /// Clawsy will auto-replace outdated blocks in agents' memory.md files.
    private static let clawsyBlockVersion = 4

    /// Ensure the agent's memory.md includes a current Clawsy integration block.
    /// Reads current content, replaces outdated block or appends if missing.
    /// Aggressively overwrites the block on every connect so the Node ID
    /// stored in memory.md always matches the currently-connected device.
    private func ensureMemoryMdUpdated() {
        guard !memoryMdUpdated, let agentId = currentAgentId else { return }
        let inboxKey = clawsyInboxSessionKey
        let nodeId = DeviceIdentity.shared.deviceId

        sendRequest(method: "agents.files.get", params: [
            "agentId": agentId,
            "name": "memory.md"
        ]) { [weak self] response in
            guard let self else { return }

            let existing: String
            if let payload = response["payload"] as? [String: Any],
               let content = payload["content"] as? String {
                existing = content
            } else {
                existing = ""
            }

            let freshBlock = self.clawsyMemoryBlock(inboxKey: inboxKey, nodeId: nodeId)

            // Block exists — always overwrite (cheap, and keeps Node ID fresh)
            if existing.contains("<!-- clawsy:start") {
                if let startRange = existing.range(of: "<!-- clawsy:start"),
                   let endRange = existing.range(of: "<!-- clawsy:end -->") {
                    // If the on-disk block is byte-identical to the fresh one, skip the write.
                    let currentBlock = String(existing[startRange.lowerBound..<endRange.upperBound])
                    if currentBlock == freshBlock {
                        self.memoryMdUpdated = true
                        self.log("memory.md: clawsy block v\(Self.clawsyBlockVersion) up to date")
                        return
                    }
                    var updated = existing
                    updated.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: freshBlock)
                    self.writeMemoryMd(agentId: agentId, content: updated)
                    return
                }
            }

            // No block yet — append
            let updated = existing.trimmingCharacters(in: .whitespacesAndNewlines)
                + "\n\n" + freshBlock + "\n"
            self.writeMemoryMd(agentId: agentId, content: updated)
        }
    }

    private func clawsyMemoryBlock(inboxKey: String, nodeId: String) -> String {
        """
        <!-- clawsy:start clawsy:v\(Self.clawsyBlockVersion) -->
        ## Clawsy Integration
        Clawsy is a macOS companion app that delivers screenshots, camera photos, clipboard content,
        and file events to the session `\(inboxKey)`.

        **Live node identity (auto-updated on every Clawsy connect):**
        - `node_id`: `\(nodeId)`
        - `platform`: `macos`
        - `inbox_session`: `\(inboxKey)`

        ⚠️ **Node ID freshness:** The value above is rewritten by Clawsy on every connect.
        Any other Node ID you find in your workspace (TOOLS.md, cheat sheets, prior notes,
        hard-coded constants) is **presumed stale**. Before invoking a Clawsy command,
        always verify the live state with `nodes(action="status")` — never rely on a
        cached ID from another file.

        **Skill reference:** For full command reference and capabilities, load the Clawsy skill:
        `clawhub install clawsy` or `skill(name="clawsy")`.
        Docs: https://raw.githubusercontent.com/iret77/clawsy/main/SKILL.md

        **Inbox behavior:** Messages in `\(inboxKey)` are context drops from the user's Mac.
        Do NOT analyze, describe, or respond to the content unprompted.
        If you must respond, keep it to a single short acknowledgment (e.g. "Received.") and
        wait — the user will follow up with context and instructions in their main conversation.

        When a user references media sent via Clawsy (e.g. "check my screenshot", "look at what I sent"),
        use `sessions_history` on session `\(inboxKey)` to find it.
        Each message is tagged with `[clawsy:<type>]` where type is screenshot, camera, clipboard,
        file-rule, or share. Messages include device name, timestamp, and target agent.

        **Sub-agents:** When spawning sub-agents, include a Clawsy context block so they can
        report progress via Mission Control. See the SKILL.md for the exact block to copy.
        <!-- clawsy:end -->
        """
    }

    private func writeMemoryMd(agentId: String, content: String) {
        sendRequest(method: "agents.files.set", params: [
            "agentId": agentId,
            "name": "memory.md",
            "content": content
        ]) { [weak self] _ in
            self?.memoryMdUpdated = true
            self?.log("memory.md: clawsy block written for agent \(agentId)")
        }
    }

    // MARK: - Send: Connected Skill Hint

    /// Send a one-time connected message to clawsy-inbox with live node
    /// identity, capability list, and a SKILL.md reference. Called after
    /// handshake completes so the agent has ground-truth info to prefer over
    /// any stale cheat-sheet (TOOLS.md, prior notes, etc.) it may have cached.
    public func sendConnectedHint() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let nodeId = DeviceIdentity.shared.deviceId
        let deviceName = Host.current().localizedName ?? "Mac"

        let message = """
        [clawsy:connected] Clawsy macOS companion (v\(version)) connected.

        Live node identity (trust this over any cached value):
          node_id:  \(nodeId)
          platform: macos
          device:   \(deviceName)
          inbox:    \(clawsyInboxSessionKey)

        Capabilities available right now:
          • screen.capture
          • camera.snap, camera.list
          • clipboard.read, clipboard.write
          • file.list, file.get, file.set (≤200 KB), file.mkdir, file.delete,
            file.move, file.copy, file.rename, file.stat, file.exists, file.rmdir,
            file.batch, file.checksum
          • file.get.chunk, file.set.chunk  (use these for payloads > 200 KB)
          • location.get

        ⚠️ Always verify the live node with `nodes(action="status")` before invoking
        a command. Any Node ID you find in TOOLS.md, AGENTS.md, or other local
        notes is presumed stale — the value above is the only source of truth.

        For full reference, load the Clawsy skill: `clawhub install clawsy`
        Or read directly: https://raw.githubusercontent.com/iret77/clawsy/main/SKILL.md
        """

        ensureClawsyInbox { [weak self] in
            guard let self else { return }
            self.sendChatMessage(message, sessionKey: self.clawsyInboxSessionKey, deliver: false)
            self.log("Sent connected skill hint (node=\(nodeId.prefix(12))…) to clawsy-inbox")
        }
    }

    // MARK: - Send: Media via clawsy-inbox

    /// Build the structured message header for clawsy-inbox messages.
    /// Includes a no-reply directive so the agent responds minimally.
    private func clawsyMessageHeader(type: String, extra: [String: String] = [:]) -> String {
        let deviceName = Host.current().localizedName ?? "Mac"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
        var lines = ["[clawsy:\(type)] [no response needed — user will follow up separately]",
                     "agent: \(currentAgentName)",
                     "device: \(deviceName)",
                     "time: \(timestamp)"]
        for (key, value) in extra.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }
        return lines.joined(separator: "\n")
    }

    /// Send an image (screenshot, camera) to the clawsy-inbox session via `chat.send` with attachments.
    public func sendImage(base64: String, mimeType: String = "image/jpeg", message: String, deliver: Bool = false) {
        let attachment: [String: Any] = [
            "type": "image",
            "mimeType": mimeType,
            "content": base64
        ]
        ensureClawsyInbox { [weak self] in
            guard let self else { return }
            self.sendChatMessage(message, sessionKey: self.clawsyInboxSessionKey, deliver: deliver, attachments: [attachment])
        }
    }

    /// Send a clawsy envelope to the clawsy-inbox session.
    /// For image-based envelopes (screenshot, camera), sends with attachments.
    /// For text-based envelopes (clipboard, share, file-rule), sends as plain message.
    public func sendEnvelope(type: String, content: Any, metadata: [String: Any] = [:]) {
        if let dict = content as? [String: Any],
           let base64 = dict["base64"] as? String {
            // Image-based: send as chat.send with attachment
            let mimeType: String
            if let format = dict["format"] as? String, format == "png" {
                mimeType = "image/png"
            } else {
                mimeType = "image/jpeg"
            }
            var extra: [String: String] = [:]
            if let device = dict["device"] as? String { extra["camera"] = device }
            let header = clawsyMessageHeader(type: type, extra: extra)
            sendImage(base64: base64, mimeType: mimeType, message: header, deliver: false)
        } else if let text = content as? String {
            // Text content (clipboard, share text)
            let header = clawsyMessageHeader(type: type)
            ensureClawsyInbox { [weak self] in
                guard let self else { return }
                self.sendChatMessage("\(header)\n\n\(text)", sessionKey: self.clawsyInboxSessionKey, deliver: false)
            }
        } else if let dict = content as? [String: Any] {
            // Structured content (file-rule, share dict)
            var extra: [String: String] = [:]
            if let ruleId = dict["ruleId"] as? String { extra["rule"] = ruleId }
            if let fileName = dict["fileName"] as? String { extra["file"] = fileName }
            if let trigger = dict["trigger"] as? String { extra["trigger"] = trigger }
            let header = clawsyMessageHeader(type: type, extra: extra)

            let body: String
            if let prompt = dict["prompt"] as? String, !prompt.isEmpty {
                body = prompt
            } else if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                      let jsonString = String(data: jsonData, encoding: .utf8) {
                body = jsonString
            } else {
                body = ""
            }
            ensureClawsyInbox { [weak self] in
                guard let self else { return }
                self.sendChatMessage("\(header)\n\n\(body)", sessionKey: self.clawsyInboxSessionKey, deliver: false)
            }
        }
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
