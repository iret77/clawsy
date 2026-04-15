import Foundation

// MARK: - Connection State

/// Single source of truth for the connection lifecycle.
/// Replaces the 6+ booleans in the old NetworkManager with a single enum.
/// Every state is explicit. No contradictory states possible.
public enum ConnectionState: Equatable, CustomStringConvertible {
    /// Not connected, no activity
    case disconnected

    /// Attempting direct WebSocket connection
    case connecting(attempt: Int)

    /// Building SSH tunnel before WebSocket
    case sshTunneling

    /// WebSocket open, performing auth handshake
    case handshaking

    /// Gateway requires manual pairing approval
    case awaitingPairing(requestId: String)

    /// Fully connected and authenticated
    case connected

    /// Connection lost, waiting to retry
    case reconnecting(attempt: Int, nextRetryIn: Int)

    /// All retries exhausted or unrecoverable error
    case failed(ConnectionFailure)

    // MARK: - Derived Properties

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var isActive: Bool {
        switch self {
        case .disconnected, .failed: return false
        default: return true
        }
    }

    /// Whether a successful handshake has been completed at least once
    /// in the current connection lifecycle. This is tracked externally
    /// by the state machine, not derived from the current state.
    /// See `ConnectionStateMachine.hasEverConnected`.

    public var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting(let n): return "Connecting (attempt \(n))"
        case .sshTunneling: return "SSH Tunnel"
        case .handshaking: return "Handshaking"
        case .awaitingPairing: return "Awaiting Pairing"
        case .connected: return "Connected"
        case .reconnecting(let n, let s): return "Reconnecting (attempt \(n), \(s)s)"
        case .failed(let f): return "Failed: \(f)"
        }
    }
}

// MARK: - Connection Failure

/// Classifies why the connection failed. Actionable, not vague.
public enum ConnectionFailure: Equatable, CustomStringConvertible {
    case originNotAllowed
    case invalidToken
    case sshTunnelFailed(String)
    case hostUnreachable
    case gatewayNotRunning
    case reconnectExhausted
    case skillMissing
    case unknown(String)

    public var description: String {
        switch self {
        case .originNotAllowed: return "Connection rejected (origin)"
        case .invalidToken: return "Invalid token"
        case .sshTunnelFailed(let d): return "SSH failed: \(d)"
        case .hostUnreachable: return "Host unreachable"
        case .gatewayNotRunning: return "Gateway not running"
        case .reconnectExhausted: return "Reconnect exhausted"
        case .skillMissing: return "Clawsy skill missing"
        case .unknown(let d): return d
        }
    }

    public var localizedTitle: String {
        switch self {
        case .originNotAllowed: return NSLocalizedString("FAILURE_ORIGIN_NOT_ALLOWED", bundle: .clawsy, comment: "")
        case .invalidToken: return NSLocalizedString("FAILURE_INVALID_TOKEN", bundle: .clawsy, comment: "")
        case .sshTunnelFailed: return NSLocalizedString("FAILURE_SSH_FAILED", bundle: .clawsy, comment: "")
        case .hostUnreachable: return NSLocalizedString("FAILURE_HOST_UNREACHABLE", bundle: .clawsy, comment: "")
        case .gatewayNotRunning: return NSLocalizedString("FAILURE_GATEWAY_NOT_RUNNING", bundle: .clawsy, comment: "")
        case .reconnectExhausted: return NSLocalizedString("FAILURE_RECONNECT_EXHAUSTED", bundle: .clawsy, comment: "")
        case .skillMissing: return NSLocalizedString("FAILURE_SKILL_MISSING", bundle: .clawsy, comment: "")
        case .unknown: return NSLocalizedString("FAILURE_UNKNOWN", bundle: .clawsy, comment: "")
        }
    }
}

// MARK: - Connection Event

/// All possible events that can trigger a state transition.
/// Events are the ONLY way to change state. No direct mutation.
public enum ConnectionEvent {
    // User actions
    case connect
    case disconnect

    // WebSocket lifecycle
    case webSocketConnected
    case webSocketDisconnected(code: UInt16, reason: String)
    case webSocketError(String)

    // Handshake
    case handshakeComplete(deviceToken: String?)
    case handshakeFailed(String)

    // Pairing
    case pairingRequired(requestId: String)
    case pairingApproved

    // SSH tunnel
    case sshTunnelReady(port: UInt16)
    case sshTunnelFailed(String)
    case sshTunnelDied

    // Retry
    case retryTimerTick
    case retryNow
}

// MARK: - Side Effect

/// Actions the state machine requests but does NOT execute itself.
/// The caller (ConnectionManager) executes these. This keeps the
/// state machine pure and testable.
public enum ConnectionSideEffect: Equatable {
    case openWebSocket(useTunnel: Bool)
    case closeWebSocket
    case startSSHTunnel
    case stopSSHTunnel
    case performHandshake
    case startRetryTimer(seconds: Int)
    case stopRetryTimer
    case notifyStateChanged
    case emitFailure(ConnectionFailure)
}

// MARK: - Connection Configuration

/// Immutable config for a connection attempt. No scattered globals.
public struct ConnectionConfig: Equatable {
    public let gatewayHost: String
    public let gatewayPort: String
    public let serverToken: String
    public let sshUser: String
    public let useSshFallback: Bool
    public let sshOnly: Bool

    /// Retry delays for first N attempts, then sustained interval
    public let retryDelays: [TimeInterval]
    /// Sustained retry interval after initial delays
    public let sustainedRetryInterval: TimeInterval
    /// Maximum total retry duration before giving up
    public let maxRetryDuration: TimeInterval

    public var hasSshConfig: Bool {
        !sshUser.isEmpty && (useSshFallback || sshOnly)
    }

    public init(
        gatewayHost: String,
        gatewayPort: String = "18789",
        serverToken: String,
        sshUser: String = "",
        useSshFallback: Bool = false,
        sshOnly: Bool = false,
        retryDelays: [TimeInterval] = [0, 5, 15, 30],
        sustainedRetryInterval: TimeInterval = 60,
        maxRetryDuration: TimeInterval = 30 * 60
    ) {
        self.gatewayHost = gatewayHost
        self.gatewayPort = gatewayPort
        self.serverToken = serverToken
        self.sshUser = sshUser
        self.useSshFallback = useSshFallback
        self.sshOnly = sshOnly
        self.retryDelays = retryDelays
        self.sustainedRetryInterval = sustainedRetryInterval
        self.maxRetryDuration = maxRetryDuration
    }
}

// MARK: - State Machine

/// Pure, deterministic state machine. No I/O, no timers, no threads.
/// Given (state, event) → returns (newState, sideEffects).
/// This is the core that makes reconnect logic testable and race-free.
public final class ConnectionStateMachine {

    // MARK: - Published State

    public private(set) var state: ConnectionState = .disconnected
    public private(set) var config: ConnectionConfig?

    /// Whether a handshake was ever completed in this lifecycle.
    /// Persists across reconnect cycles, cleared only on user disconnect.
    public private(set) var hasEverConnected: Bool = false

    /// Whether the last successful connection used SSH.
    /// Used to skip WSS on reconnect and go straight to SSH.
    public private(set) var lastConnectionUsedSSH: Bool = false

    /// The SSH tunnel local port (set when tunnel is ready)
    public private(set) var sshTunnelPort: UInt16 = 0

    /// When retries started (for 30-min timeout)
    private var retryStartTime: Date?

    /// Current retry attempt (resets on successful connect)
    private var retryAttempt: Int = 0

    // MARK: - Transition

    /// Process an event and return the side effects to execute.
    /// This is the ONLY way to change state.
    @discardableResult
    public func handle(_ event: ConnectionEvent) -> [ConnectionSideEffect] {
        let (newState, effects) = transition(from: state, on: event)
        if newState != state {
            state = newState
            return [.notifyStateChanged] + effects
        }
        return effects
    }

    /// Configure for a new connection. Must be called before .connect event.
    public func configure(_ config: ConnectionConfig) {
        self.config = config
    }

    /// Full reset — called on user-initiated disconnect or host removal.
    public func reset() {
        state = .disconnected
        hasEverConnected = false
        lastConnectionUsedSSH = false
        sshTunnelPort = 0
        retryStartTime = nil
        retryAttempt = 0
    }

    // MARK: - Transition Logic

    private func transition(
        from state: ConnectionState,
        on event: ConnectionEvent
    ) -> (ConnectionState, [ConnectionSideEffect]) {

        switch (state, event) {

        // ── CONNECT ──────────────────────────────────────────────────────

        case (.disconnected, .connect),
             (.failed, .connect):
            retryAttempt = 0
            retryStartTime = nil
            guard let config = config, !config.serverToken.isEmpty else {
                return (.failed(.unknown("Missing configuration")), [])
            }
            if config.sshOnly && config.hasSshConfig {
                return (.sshTunneling, [.startSSHTunnel])
            }
            return (.connecting(attempt: 1), [.openWebSocket(useTunnel: false)])

        // ── DISCONNECT (user-initiated) ──────────────────────────────────

        case (_, .disconnect):
            reset()
            return (.disconnected, [.closeWebSocket, .stopSSHTunnel, .stopRetryTimer])

        // ── WEBSOCKET CONNECTED ──────────────────────────────────────────

        case (.connecting, .webSocketConnected):
            return (.handshaking, [.performHandshake])

        // ── HANDSHAKE ────────────────────────────────────────────────────

        case (.handshaking, .handshakeComplete(let token)):
            hasEverConnected = true
            lastConnectionUsedSSH = (sshTunnelPort > 0)
            retryAttempt = 0
            retryStartTime = nil
            // Store device token via side effect if needed
            let _ = token // Token storage is handled by the caller
            return (.connected, [.stopRetryTimer])

        case (.handshaking, .handshakeFailed(let reason)):
            let failure = classifyHandshakeFailure(reason)
            return (.failed(failure), [.closeWebSocket, .stopSSHTunnel])

        // ── PAIRING ──────────────────────────────────────────────────────

        case (.handshaking, .pairingRequired(let requestId)):
            return (.awaitingPairing(requestId: requestId), [])

        case (.awaitingPairing, .pairingApproved):
            // After pairing, gateway sends hello-ok which triggers handshakeComplete
            return (.handshaking, [])

        // ── WEBSOCKET DISCONNECT (unexpected) ────────────────────────────

        case (.connected, .webSocketDisconnected(let code, let reason)):
            let failure = classifyDisconnect(code: code, reason: reason)
            if let failure {
                // Known fatal error — don't retry
                return (.failed(failure), [.stopSSHTunnel, .emitFailure(failure)])
            }
            // Unexpected disconnect — enter reconnect
            return enterReconnect()

        case (.connected, .webSocketError):
            return enterReconnect()

        case (.handshaking, .webSocketDisconnected),
             (.handshaking, .webSocketError):
            if hasEverConnected {
                // Was connected before → reconnect
                return enterReconnect()
            }
            // First-time failure → try SSH fallback
            return trySshFallbackOrFail()

        case (.connecting, .webSocketDisconnected),
             (.connecting, .webSocketError):
            if hasEverConnected {
                return enterReconnect()
            }
            return trySshFallbackOrFail()

        // ── SSH TUNNEL ───────────────────────────────────────────────────

        case (.sshTunneling, .sshTunnelReady(let port)):
            sshTunnelPort = port
            return (.connecting(attempt: retryAttempt + 1), [.openWebSocket(useTunnel: true)])

        case (.sshTunneling, .sshTunnelFailed(let reason)):
            if hasEverConnected {
                // SSH reconnect failed — schedule retry
                return scheduleRetry()
            }
            return (.failed(.sshTunnelFailed(reason)), [.emitFailure(.sshTunnelFailed(reason))])

        case (.connected, .sshTunnelDied):
            // SSH tunnel died while connected — enter reconnect
            return enterReconnect(viaSSH: true)

        // ── RETRY ────────────────────────────────────────────────────────

        case (.reconnecting(let attempt, let countdown), .retryTimerTick):
            let newCountdown = countdown - 1
            if newCountdown <= 0 {
                return (.reconnecting(attempt: attempt, nextRetryIn: 0), [.stopRetryTimer])
            }
            return (.reconnecting(attempt: attempt, nextRetryIn: newCountdown), [])

        case (.reconnecting, .retryNow):
            if isRetryExhausted() {
                return (.failed(.reconnectExhausted), [.stopRetryTimer, .emitFailure(.reconnectExhausted)])
            }
            if lastConnectionUsedSSH && config?.hasSshConfig == true {
                sshTunnelPort = 0
                return (.sshTunneling, [.startSSHTunnel])
            }
            retryAttempt += 1
            return (.connecting(attempt: retryAttempt), [.openWebSocket(useTunnel: false)])

        // ── DEFAULT (ignore unexpected events) ───────────────────────────

        default:
            return (state, [])
        }
    }

    // MARK: - Helpers

    private func enterReconnect(viaSSH: Bool = false) -> (ConnectionState, [ConnectionSideEffect]) {
        var effects: [ConnectionSideEffect] = [.closeWebSocket]
        if viaSSH {
            effects.append(.stopSSHTunnel)
            sshTunnelPort = 0
        }

        if retryStartTime == nil {
            retryStartTime = Date()
        }

        if isRetryExhausted() {
            return (.failed(.reconnectExhausted), effects + [.emitFailure(.reconnectExhausted)])
        }

        let delay = retryDelay(for: retryAttempt)
        retryAttempt += 1

        if delay == 0 {
            // Immediate retry
            if lastConnectionUsedSSH && config?.hasSshConfig == true {
                sshTunnelPort = 0
                return (.sshTunneling, effects + [.startSSHTunnel])
            }
            return (.connecting(attempt: retryAttempt), effects + [.openWebSocket(useTunnel: false)])
        }

        let seconds = max(Int(delay.rounded(.up)), 1)
        return (.reconnecting(attempt: retryAttempt, nextRetryIn: seconds),
                effects + [.startRetryTimer(seconds: seconds)])
    }

    private func scheduleRetry() -> (ConnectionState, [ConnectionSideEffect]) {
        if retryStartTime == nil {
            retryStartTime = Date()
        }

        if isRetryExhausted() {
            return (.failed(.reconnectExhausted), [.emitFailure(.reconnectExhausted)])
        }

        let delay = retryDelay(for: retryAttempt)
        retryAttempt += 1
        let seconds = max(Int(delay.rounded(.up)), 1)
        return (.reconnecting(attempt: retryAttempt, nextRetryIn: seconds),
                [.startRetryTimer(seconds: seconds)])
    }

    private func trySshFallbackOrFail() -> (ConnectionState, [ConnectionSideEffect]) {
        guard let config = config, config.hasSshConfig else {
            return (.failed(.hostUnreachable), [.emitFailure(.hostUnreachable)])
        }
        return (.sshTunneling, [.startSSHTunnel])
    }

    private func retryDelay(for attempt: Int) -> TimeInterval {
        guard let config = config else { return 5 }
        if attempt < config.retryDelays.count {
            return config.retryDelays[attempt]
        }
        return config.sustainedRetryInterval
    }

    private func isRetryExhausted() -> Bool {
        guard let start = retryStartTime, let config = config else { return false }
        return Date().timeIntervalSince(start) >= config.maxRetryDuration
    }

    private func classifyDisconnect(code: UInt16, reason: String) -> ConnectionFailure? {
        let lower = reason.lowercased()
        if lower.contains("origin not allowed") || lower.contains("origin_not_allowed") {
            return .originNotAllowed
        }
        if lower.contains("invalid_token") || lower.contains("auth_token_mismatch") {
            return .invalidToken
        }
        // Normal closure or empty reason = reconnectable
        return nil
    }

    private func classifyHandshakeFailure(_ reason: String) -> ConnectionFailure {
        let lower = reason.lowercased()
        if lower.contains("origin") { return .originNotAllowed }
        if lower.contains("token") || lower.contains("auth") { return .invalidToken }
        return .unknown(reason)
    }
}
