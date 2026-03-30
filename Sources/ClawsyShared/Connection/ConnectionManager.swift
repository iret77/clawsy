import Foundation
import Combine
import os.log

// MARK: - Connection Manager

/// Orchestrates the connection lifecycle by wiring together:
/// - `ConnectionStateMachine` (pure state transitions)
/// - `WebSocketTransport` (WebSocket I/O)
/// - `SSHTunnelManager` (SSH tunnel process)
///
/// Exposes `@Published` properties for SwiftUI observation.
/// Replaces the monolithic NetworkManager for connection concerns.
public final class ConnectionManager: ObservableObject {

    // MARK: - Published State (for SwiftUI)

    @Published public private(set) var state: ConnectionState = .disconnected
    @Published public private(set) var connectionFailure: ConnectionFailure?
    @Published public private(set) var retryCountdown: Int = 0

    /// Raw log for debug view
    @Published public var rawLog: String = ""

    // MARK: - Components

    public let stateMachine = ConnectionStateMachine()
    public let transport = WebSocketTransport()

    #if os(macOS)
    public let sshTunnel = SSHTunnelManager()
    #endif

    // MARK: - Callbacks

    /// Called when WebSocket receives a text message (for command routing)
    public var onMessage: ((String) -> Void)?

    /// Called when state changes to .connected
    public var onConnected: (() -> Void)?

    /// Called when connection is lost (for UI updates)
    public var onDisconnected: (() -> Void)?

    // MARK: - Private

    private let logger = OSLog(subsystem: "ai.clawsy", category: "Connection")
    private var retryTimer: Timer?
    private var config: ConnectionConfig?

    // MARK: - Init

    public init() {
        wireTransport()
        #if os(macOS)
        wireSSHTunnel()
        #endif
    }

    // MARK: - Public API

    /// Configure and start a connection.
    public func connect(config: ConnectionConfig) {
        self.config = config
        stateMachine.configure(config)

        let startDate = ISO8601DateFormatter().string(from: Date())
        rawLog = "[LOG START] \(startDate)\n"
        log("Connecting to \(config.gatewayHost):\(config.gatewayPort)")

        let effects = stateMachine.handle(.connect)
        execute(effects)
    }

    /// Disconnect (user-initiated). Clears all state.
    public func disconnect() {
        log("User disconnected")
        let effects = stateMachine.handle(.disconnect)
        execute(effects)
    }

    /// Send a text message over the WebSocket.
    @discardableResult
    public func send(_ text: String) -> Bool {
        transport.send(text)
    }

    /// Send a JSON dictionary over the WebSocket.
    @discardableResult
    public func sendJSON(_ dict: [String: Any]) -> Bool {
        transport.sendJSON(dict)
    }

    /// Whether the connection is fully established (handshake complete).
    public var isConnected: Bool {
        state.isConnected
    }

    /// The base URL for REST API calls (SSH-tunnel-aware).
    public var gatewayBaseURL: String? {
        guard let config = config else { return nil }
        #if os(macOS)
        if sshTunnel.isRunning {
            return "http://127.0.0.1:\(sshTunnel.localPort)"
        }
        #endif
        let host = config.gatewayHost.isEmpty ? "127.0.0.1" : config.gatewayHost
        let port = config.gatewayPort.isEmpty ? "18789" : config.gatewayPort
        if host.contains("://") { return host }
        return "http://\(host):\(port)"
    }

    // MARK: - Wire Components

    private func wireTransport() {
        transport.onConnected = { [weak self] in
            self?.log("WebSocket connected")
            self?.processEvent(.webSocketConnected)
        }

        transport.onDisconnected = { [weak self] code, reason in
            self?.log("WebSocket disconnected: \(code) \(reason)")
            self?.processEvent(.webSocketDisconnected(code: code, reason: reason))
        }

        transport.onError = { [weak self] error in
            self?.log("WebSocket error: \(error)")
            self?.processEvent(.webSocketError(error))
        }

        transport.onMessage = { [weak self] text in
            self?.onMessage?(text)
        }
    }

    #if os(macOS)
    private func wireSSHTunnel() {
        sshTunnel.onTunnelReady = { [weak self] port in
            self?.log("SSH tunnel ready on port \(port)")
            self?.processEvent(.sshTunnelReady(port: port))
        }

        sshTunnel.onTunnelFailed = { [weak self] reason in
            self?.log("SSH tunnel failed: \(reason)")
            self?.processEvent(.sshTunnelFailed(reason))
        }

        sshTunnel.onTunnelDied = { [weak self] in
            self?.log("SSH tunnel died")
            self?.processEvent(.sshTunnelDied)
        }

        sshTunnel.onLog = { [weak self] message in
            self?.rawLog += "\n\(message)"
        }
    }
    #endif

    // MARK: - Event Processing

    private func processEvent(_ event: ConnectionEvent) {
        let effects = stateMachine.handle(event)
        execute(effects)
    }

    // MARK: - Side Effect Execution

    private func execute(_ effects: [ConnectionSideEffect]) {
        for effect in effects {
            switch effect {
            case .openWebSocket(let useTunnel):
                openWebSocket(useTunnel: useTunnel)

            case .closeWebSocket:
                transport.disconnect()

            case .startSSHTunnel:
                #if os(macOS)
                guard let config = config else { return }
                sshTunnel.start(
                    host: config.gatewayHost,
                    sshUser: config.sshUser,
                    gatewayPort: config.gatewayPort
                )
                #endif

            case .stopSSHTunnel:
                #if os(macOS)
                sshTunnel.stop()
                #endif

            case .performHandshake:
                // Handshake is handled by the command layer (HandshakeManager),
                // which will call processEvent(.handshakeComplete) or (.handshakeFailed)
                onConnected?()

            case .startRetryTimer(let seconds):
                startRetryTimer(seconds: seconds)

            case .stopRetryTimer:
                stopRetryTimer()

            case .notifyStateChanged:
                syncPublishedState()

            case .emitFailure(let failure):
                DispatchQueue.main.async { [weak self] in
                    self?.connectionFailure = failure
                }
            }
        }
    }

    // MARK: - WebSocket URL Construction

    private func openWebSocket(useTunnel: Bool) {
        guard let config = config else { return }

        let urlString: String
        if useTunnel {
            #if os(macOS)
            urlString = "ws://127.0.0.1:\(sshTunnel.localPort)"
            #else
            urlString = "ws://127.0.0.1:18789"
            #endif
        } else {
            let host = config.gatewayHost
            let port = config.gatewayPort
            let scheme = (host.contains("localhost") || host.contains("127.0.0.1")) ? "ws" : "wss"
            urlString = "\(scheme)://\(host):\(port)"
        }

        guard let url = URL(string: urlString) else {
            log("Invalid WebSocket URL: \(urlString)")
            processEvent(.webSocketError("Invalid URL: \(urlString)"))
            return
        }

        // When tunneling, the URL is localhost but the gateway checks the Origin header
        // against the real hostname. Set it explicitly so the origin check passes.
        let origin: String? = useTunnel ? "http://\(config.gatewayHost)" : nil

        let timeout: TimeInterval = useTunnel ? 12.0 : 8.0
        log("Opening WebSocket to \(urlString) (timeout: \(Int(timeout))s)")
        transport.connect(to: url, timeout: timeout, origin: origin)
    }

    // MARK: - Retry Timer

    private func startRetryTimer(seconds: Int) {
        stopRetryTimer()
        retryCountdown = seconds
        log("Retry in \(seconds)s")

        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            self.processEvent(.retryTimerTick)

            if self.stateMachine.state == .reconnecting(attempt: 0, nextRetryIn: 0) {
                // Timer tick reduced countdown to 0 — but we need to check the actual state
            }

            // Check if countdown reached zero
            if case .reconnecting(_, let remaining) = self.stateMachine.state, remaining <= 0 {
                timer.invalidate()
                self.retryTimer = nil
                self.processEvent(.retryNow)
            }
        }
    }

    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
        retryCountdown = 0
    }

    // MARK: - State Sync

    private func syncPublishedState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let newState = self.stateMachine.state
            self.state = newState

            if case .reconnecting(_, let countdown) = newState {
                self.retryCountdown = countdown
            } else {
                self.retryCountdown = 0
            }

            if case .failed(let failure) = newState {
                self.connectionFailure = failure
            }

            // Notify disconnection
            if case .disconnected = newState {
                self.onDisconnected?()
            }
            if case .failed = newState {
                self.onDisconnected?()
            }
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        os_log("[Connection] %{public}@", log: logger, type: .info, message)
        DispatchQueue.main.async { [weak self] in
            self?.rawLog += "\n[CONN] \(message)"
        }
    }

    // MARK: - State Machine Access (for HandshakeManager)

    /// Called by HandshakeManager when handshake completes.
    public func handleHandshakeComplete(deviceToken: String?) {
        processEvent(.handshakeComplete(deviceToken: deviceToken))
    }

    /// Called by HandshakeManager when handshake fails.
    public func handleHandshakeFailed(_ reason: String) {
        processEvent(.handshakeFailed(reason))
    }

    /// Called by HandshakeManager when pairing is required.
    public func handlePairingRequired(requestId: String) {
        processEvent(.pairingRequired(requestId: requestId))
    }

    /// Called by HandshakeManager when pairing is approved.
    public func handlePairingApproved() {
        processEvent(.pairingApproved)
    }
}
