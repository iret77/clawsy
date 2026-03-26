import Foundation
import os.log

// MARK: - Handshake Manager

/// Handles the OpenClaw Protocol V3 handshake sequence:
/// 1. Wait for `connect.challenge` (nonce)
/// 2. Send `connect` request with device identity + V3 signature
/// 3. Handle `hello-ok` (success) or pairing flow or error
///
/// Stateless per handshake — create a new flow per connection attempt.
public final class HandshakeManager {

    // MARK: - Callbacks

    public var onHandshakeComplete: ((HandshakeResult) -> Void)?
    public var onPairingRequired: ((String) -> Void)?  // requestId
    public var onHandshakeFailed: ((String) -> Void)?

    // MARK: - Configuration

    public struct Config {
        public let gatewayToken: String
        public let deviceToken: String?
        public let capabilities: [String]
        public let commands: [String]
        public let permissions: [String: Bool]
        public let role: String
        public let scopes: [String]
        public let displayName: String?

        public init(
            gatewayToken: String,
            deviceToken: String? = nil,
            capabilities: [String] = ["camera", "screen"],
            commands: [String] = [
                "camera.snap", "camera.list",
                "screen.capture",
                "clipboard.read", "clipboard.write",
                "file.list", "file.get", "file.set", "file.mkdir",
                "file.delete", "file.move", "file.copy",
                "file.get.chunk", "file.set.chunk",
                "file.stat", "file.exists"
            ],
            permissions: [String: Bool] = [:],
            role: String = "node",
            scopes: [String] = ["operator.read"],
            displayName: String? = nil
        ) {
            self.gatewayToken = gatewayToken
            self.deviceToken = deviceToken
            self.capabilities = capabilities
            self.commands = commands
            self.permissions = permissions
            self.role = role
            self.scopes = scopes
            self.displayName = displayName
        }
    }

    // MARK: - Handshake Result

    public struct HandshakeResult {
        public let protocol_: Int
        public let deviceToken: String?
        public let serverVersion: String?
        public let connId: String?
        public let policy: Policy?
        public let features: Features?

        public struct Policy {
            public let maxPayload: Int
            public let tickIntervalMs: Int
        }

        public struct Features {
            public let methods: [String]
            public let events: [String]
        }
    }

    // MARK: - State

    private var config: Config
    private var pendingNonce: String?
    private var connectRequestId: String?
    private let logger = OSLog(subsystem: "ai.clawsy", category: "Handshake")

    // MARK: - Constants

    private static let clientId = "openclaw-macos"
    private static let clientMode = "node"
    private static let platform = "macos"
    private static let protocolVersion = 3

    // MARK: - Init

    public init(config: Config) {
        self.config = config
    }

    /// Update config (e.g., after receiving a new device token)
    public func updateConfig(_ config: Config) {
        self.config = config
    }

    // MARK: - Public API

    /// Process an incoming WebSocket message during handshake.
    /// Returns true if the message was consumed by the handshake flow.
    @discardableResult
    public func processMessage(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        guard let type = json["type"] as? String else { return false }

        switch type {
        case "event":
            return handleEvent(json)
        case "res":
            return handleResponse(json)
        default:
            return false
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ json: [String: Any]) -> Bool {
        guard let event = json["event"] as? String else { return false }

        switch event {
        case "connect.challenge":
            return handleChallenge(json)

        case "device.pair.requested":
            if let payload = json["payload"] as? [String: Any],
               let requestId = payload["requestId"] as? String {
                onPairingRequired?(requestId)
                return true
            }
            return false

        case "device.pair.resolved":
            if let payload = json["payload"] as? [String: Any],
               let decision = payload["decision"] as? String,
               decision == "approved" {
                // Pairing approved — gateway will send hello-ok next
                os_log("[Handshake] Pairing approved", log: logger)
                return true
            }
            return false

        default:
            return false
        }
    }

    // MARK: - Challenge → Connect

    private func handleChallenge(_ json: [String: Any]) -> Bool {
        guard let payload = json["payload"] as? [String: Any],
              let nonce = payload["nonce"] as? String else {
            onHandshakeFailed?("Invalid challenge: missing nonce")
            return true
        }

        os_log("[Handshake] Received challenge (nonce: %{public}@)", log: logger, nonce.prefix(8) + "...")
        pendingNonce = nonce

        // Build and send connect request
        guard let connectRequest = buildConnectRequest(nonce: nonce) else {
            onHandshakeFailed?("Failed to build connect request (signing failed)")
            return true
        }

        connectRequestId = connectRequest["id"] as? String
        onSendMessage?(connectRequest)
        return true
    }

    /// Callback to send a JSON message over the WebSocket.
    /// Set by ConnectionManager before starting handshake.
    public var onSendMessage: (([String: Any]) -> Void)?

    // MARK: - Response Handling

    private func handleResponse(_ json: [String: Any]) -> Bool {
        guard let id = json["id"] as? String,
              id == connectRequestId else {
            return false
        }

        if let ok = json["ok"] as? Bool, ok,
           let payload = json["payload"] as? [String: Any] {
            return handleHelloOk(payload)
        }

        // Error response
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown handshake error"
            let details = error["details"] as? [String: Any]
            let code = details?["code"] as? String ?? ""

            os_log("[Handshake] Failed: %{public}@ (%{public}@)", log: logger, message, code)
            onHandshakeFailed?(message)
            return true
        }

        onHandshakeFailed?("Unexpected response format")
        return true
    }

    // MARK: - hello-ok

    private func handleHelloOk(_ payload: [String: Any]) -> Bool {
        guard let type = payload["type"] as? String, type == "hello-ok" else {
            // Could be a pairing response — check
            if let type = payload["type"] as? String, type == "pair-wait" {
                os_log("[Handshake] Pairing wait — device needs approval", log: logger)
                if let requestId = payload["requestId"] as? String {
                    onPairingRequired?(requestId)
                }
                return true
            }
            onHandshakeFailed?("Expected hello-ok, got: \(payload["type"] ?? "unknown")")
            return true
        }

        os_log("[Handshake] hello-ok received", log: logger)

        // Extract device token
        let auth = payload["auth"] as? [String: Any]
        let deviceToken = auth?["deviceToken"] as? String

        // Extract policy
        let policyDict = payload["policy"] as? [String: Any]
        let policy = policyDict.map { dict in
            HandshakeResult.Policy(
                maxPayload: dict["maxPayload"] as? Int ?? 1_048_576,
                tickIntervalMs: dict["tickIntervalMs"] as? Int ?? 15000
            )
        }

        // Extract features
        let featuresDict = payload["features"] as? [String: Any]
        let features = featuresDict.map { dict in
            HandshakeResult.Features(
                methods: dict["methods"] as? [String] ?? [],
                events: dict["events"] as? [String] ?? []
            )
        }

        // Extract server info
        let server = payload["server"] as? [String: Any]

        let result = HandshakeResult(
            protocol_: payload["protocol"] as? Int ?? Self.protocolVersion,
            deviceToken: deviceToken,
            serverVersion: server?["version"] as? String,
            connId: server?["connId"] as? String,
            policy: policy,
            features: features
        )

        onHandshakeComplete?(result)
        return true
    }

    // MARK: - Build Connect Request

    private func buildConnectRequest(nonce: String) -> [String: Any]? {
        let identity = DeviceIdentity.shared
        let requestId = UUID().uuidString

        // Build device auth payload with V3 signature
        guard let deviceAuth = identity.deviceAuthPayload(
            clientId: Self.clientId,
            clientMode: Self.clientMode,
            role: config.role,
            scopes: config.scopes,
            authToken: config.gatewayToken,
            nonce: nonce
        ) else {
            return nil
        }

        // Get Mac device info
        let deviceFamily = getMacDeviceFamily()
        let modelIdentifier = getMacModelIdentifier()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        // Build auth dict
        var auth: [String: Any] = [:]
        if !config.gatewayToken.isEmpty {
            auth["token"] = config.gatewayToken
        }
        if let deviceToken = config.deviceToken, !deviceToken.isEmpty {
            auth["deviceToken"] = deviceToken
        }

        // Build client dict
        var client: [String: Any] = [
            "id": Self.clientId,
            "version": appVersion,
            "platform": Self.platform,
            "deviceFamily": deviceFamily,
            "modelIdentifier": modelIdentifier,
            "mode": Self.clientMode
        ]
        if let name = config.displayName, !name.isEmpty {
            client["displayName"] = name
        }

        // Build permissions dict
        var permissions: [String: Bool] = [
            "screen.capture": true,
            "camera.snap": true,
            "clipboard.read": true,
            "clipboard.write": true,
            "file.read": true,
            "file.write": true
        ]
        for (key, value) in config.permissions {
            permissions[key] = value
        }

        // Build params
        let params: [String: Any] = [
            "minProtocol": Self.protocolVersion,
            "maxProtocol": Self.protocolVersion,
            "client": client,
            "role": config.role,
            "scopes": config.scopes,
            "caps": config.capabilities,
            "commands": config.commands,
            "permissions": permissions,
            "auth": auth,
            "device": deviceAuth,
            "locale": Locale.current.identifier,
            "userAgent": "clawsy-macos/\(appVersion)"
        ]

        return [
            "type": "req",
            "id": requestId,
            "method": "connect",
            "params": params
        ]
    }

    // MARK: - Mac Device Info

    private func getMacDeviceFamily() -> String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelStr = String(cString: model)

        if modelStr.contains("MacBookPro") { return "MacBookPro" }
        if modelStr.contains("MacBookAir") { return "MacBookAir" }
        if modelStr.contains("MacBook") { return "MacBook" }
        if modelStr.contains("Macmini") { return "MacMini" }
        if modelStr.contains("MacPro") { return "MacPro" }
        if modelStr.contains("iMac") { return "iMac" }
        return "Mac"
        #else
        return "Mac"
        #endif
    }

    private func getMacModelIdentifier() -> String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #else
        return "Mac"
        #endif
    }
}
