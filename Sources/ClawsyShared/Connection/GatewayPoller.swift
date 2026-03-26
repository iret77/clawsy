import Foundation
import Combine
import os.log

// MARK: - Gateway Poller

/// Polls the gateway REST API for agents and sessions.
/// Replaces the session polling that was buried in the old NetworkManager.
/// Runs independently of the WebSocket connection.
public final class GatewayPoller: ObservableObject {

    @Published public var agents: [GatewayAgent] = []
    @Published public var sessions: [GatewaySession] = []

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
    private var baseURL: String?
    private var token: String?

    public init(interval: TimeInterval = 30) {
        self.interval = interval
        self.targetSessionKey = SharedConfig.sharedDefaults.string(forKey: "targetSessionKey") ?? "main"
    }

    /// Start polling against the given gateway base URL.
    public func start(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
        stop()
        poll() // immediate first poll
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

    // MARK: - Polling

    private func poll() {
        fetchAgents()
        fetchSessions()
    }

    private func fetchAgents() {
        guard let baseURL = baseURL, let token = token else { return }
        guard let url = URL(string: "\(baseURL)/agents/list") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let agentsList = json["agents"] as? [[String: Any]] else {
                return
            }

            let parsed: [GatewayAgent] = agentsList.compactMap { a in
                guard let id = a["id"] as? String, let name = a["name"] as? String else { return nil }
                return GatewayAgent(id: id, name: name)
            }

            DispatchQueue.main.async {
                self?.agents = parsed
            }
        }.resume()
    }

    private func fetchSessions() {
        guard let baseURL = baseURL, let token = token else { return }
        guard let url = URL(string: "\(baseURL)/sessions/list") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionsList = json["sessions"] as? [[String: Any]] else {
                return
            }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let parsed: [GatewaySession] = sessionsList.compactMap { s in
                guard let key = s["key"] as? String else { return nil }
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
                self?.sessions = parsed
            }
        }.resume()
    }

    // MARK: - Send Events via REST

    /// Send messages to agent sessions via the WebSocket.
    public var onSendWebSocket: (([String: Any]) -> Void)?

    /// Send a message to an agent session via Protocol V3 `chat.send`.
    /// This is the same method the official OpenClaw app uses.
    public func sendMessage(_ message: String, sessionKey: String, deliver: Bool = false) {
        let frame: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "chat.send",
            "params": [
                "sessionKey": sessionKey,
                "message": message,
                "deliver": deliver,
                "idempotencyKey": UUID().uuidString
            ]
        ]

        onSendWebSocket?(frame)
    }

    /// Send a clawsy_envelope as a chat message to the target session.
    /// Wraps the envelope JSON in a message that the agent can parse.
    public func sendEnvelope(_ jsonString: String, sessionKey: String, deliver: Bool = false) {
        sendMessage(jsonString, sessionKey: sessionKey, deliver: deliver)
    }
}
