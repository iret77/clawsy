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
    @Published public var targetSessionKey: String = "clawsy-service" {
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
        self.targetSessionKey = SharedConfig.sharedDefaults.string(forKey: "targetSessionKey") ?? "clawsy-service"
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

    /// Send a clawsy_envelope to the gateway via Protocol V3 `node.event`.
    /// This goes over the existing WebSocket connection, not REST.
    public var onSendWebSocket: (([String: Any]) -> Void)?

    /// Send a clawsy_envelope to the gateway.
    /// Routes through the WebSocket as a `node.event` frame (Protocol V3).
    public func sendEnvelope(_ jsonString: String, sessionKey: String, deliver: Bool = false) {
        let payload: [String: Any] = [
            "sessionKey": sessionKey,
            "message": jsonString,
            "deliver": deliver
        ]

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else { return }

        let frame: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "node.event",
            "params": [
                "event": "clawsy_envelope",
                "payloadJSON": payloadJSON
            ]
        ]

        onSendWebSocket?(frame)
    }

    /// Fallback: Send via REST API (for contexts without WS, e.g. Share Extension)
    public func sendEnvelopeREST(_ jsonString: String, sessionKey: String, deliver: Bool = false) {
        guard let baseURL = baseURL, let token = token else { return }

        // Try the system-event endpoint (standard OpenClaw API)
        guard let url = URL(string: "\(baseURL)/api/sessions/\(sessionKey)/events") else { return }

        let body: [String: Any] = [
            "message": jsonString,
            "deliver": deliver
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
}
