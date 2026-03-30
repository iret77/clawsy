import Foundation
import Combine
import os.log

// MARK: - Host Connection State

/// Aggregated state for one host, exposed to UI
public struct HostConnectionState: Equatable {
    public var connectionState: ConnectionState = .disconnected
    public var failure: ConnectionFailure? = nil
    public var retryCountdown: Int = 0
    public var gatewayVersion: String? = nil
    public var connId: String? = nil
    public var pairingRequestId: String? = nil
    public var nodeConnected: Bool = false
}

// MARK: - Host Manager

/// Manages multiple host profiles and their connections.
/// Each host gets its own ConnectionManager + HandshakeManager + CommandRouter.
/// The active host's state is forwarded to the UI via @Published properties.
public class HostManager: ObservableObject {
    private let logger = OSLog(subsystem: "ai.clawsy", category: "HostManager")

    // MARK: - Profile Management

    @Published public var profiles: [HostProfile] = []
    @Published public var activeHostId: UUID?

    // MARK: - Active Host State (forwarded to UI)

    @Published public var state: ConnectionState = .disconnected
    @Published public var failure: ConnectionFailure? = nil
    @Published public var retryCountdown: Int = 0
    @Published public var pairingRequestId: String? = nil
    @Published public var rawLog: String = ""

    // MARK: - Per-Host Connections

    /// Connection managers, one per host profile
    private var connections: [UUID: ConnectionManager] = [:]

    /// Handshake managers, one per host profile
    private var handshakes: [UUID: HandshakeManager] = [:]

    /// Command routers, one per host profile
    public var commandRouters: [UUID: CommandRouter] = [:]

    /// Node connection managers (second WS as role=node), one per host profile
    private var nodeConnections: [UUID: NodeConnectionManager] = [:]

    /// Gateway pollers (agents/sessions), one per host profile
    private var pollers: [UUID: GatewayPoller] = [:]

    /// Per-host connection state (for multi-host status views)
    @Published public var hostStates: [UUID: HostConnectionState] = [:]

    private var activeCancellables = Set<AnyCancellable>()
    private var nodeCancellables = Set<AnyCancellable>()
    private var perHostCancellables: [UUID: AnyCancellable] = [:]

    // MARK: - Callbacks (set by AppDelegate/ContentView)

    /// Called when a command requires user approval (screenshot, clipboard.read, camera)
    public var onApprovalRequired: ((
        _ hostId: UUID,
        _ command: String,
        _ params: [String: Any],
        _ completion: @escaping (Bool) -> Void
    ) -> Void)?

    /// Called when an agent sends a response to a QuickSend message
    public var onAgentResponse: ((_ agentName: String, _ message: String, _ sessionKey: String) -> Void)?

    /// Called when a command handler needs to execute a platform action
    public var onRegisterHandlers: ((_ router: CommandRouter, _ hostId: UUID) -> Void)?

    /// Called when file command handlers need to be registered on the node connection's router
    public var onRegisterNodeHandlers: ((_ router: CommandRouter, _ hostId: UUID) -> Void)?

    // MARK: - Convenience

    public var activeProfile: HostProfile? {
        guard let id = activeHostId else { return profiles.first }
        return profiles.first(where: { $0.id == id })
    }

    public var activeConnection: ConnectionManager? {
        guard let id = activeHostId ?? profiles.first?.id else { return nil }
        return connections[id]
    }

    public var activeRouter: CommandRouter? {
        guard let id = activeHostId ?? profiles.first?.id else { return nil }
        return commandRouters[id]
    }

    public var activePoller: GatewayPoller? {
        guard let id = activeHostId ?? profiles.first?.id else { return nil }
        return pollers[id]
    }

    public var isConnected: Bool {
        state.isConnected
    }

    // MARK: - Init

    public init() {
        loadProfiles()
        migrateFromLegacyIfNeeded()
    }

    // MARK: - Profile Persistence

    private func loadProfiles() {
        let defaults = SharedConfig.sharedDefaults
        if let data = defaults.data(forKey: "hostProfiles"),
           let decoded = try? JSONDecoder().decode([HostProfile].self, from: data) {
            self.profiles = decoded
        }
        if let activeId = defaults.string(forKey: "activeHostId"),
           let uuid = UUID(uuidString: activeId) {
            self.activeHostId = uuid
        }
        if activeHostId == nil || !profiles.contains(where: { $0.id == activeHostId }) {
            activeHostId = profiles.first?.id
        }
    }

    public func saveProfiles() {
        let defaults = SharedConfig.sharedDefaults
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: "hostProfiles")
        }
        if let activeId = activeHostId {
            defaults.set(activeId.uuidString, forKey: "activeHostId")
        }
        defaults.synchronize()

        // Keep legacy keys in sync for FinderSync/Share Extension
        if let active = activeProfile {
            defaults.set(active.gatewayHost, forKey: "serverHost")
            defaults.set(active.gatewayPort, forKey: "serverPort")
            defaults.set(active.serverToken, forKey: "serverToken")
            defaults.set(active.sshUser, forKey: "sshUser")
            defaults.set(active.useSshFallback, forKey: "useSshFallback")
            defaults.set(active.sharedFolderPath, forKey: "sharedFolderPath")
            defaults.synchronize()
        }
    }

    // MARK: - Legacy Migration

    private func migrateFromLegacyIfNeeded() {
        guard profiles.isEmpty else { return }
        let defaults = SharedConfig.sharedDefaults
        guard let legacyHost = defaults.string(forKey: "serverHost"), !legacyHost.isEmpty else { return }

        let profile = HostProfile(
            name: legacyHost,
            gatewayHost: legacyHost,
            gatewayPort: defaults.string(forKey: "serverPort") ?? "18789",
            serverToken: defaults.string(forKey: "serverToken") ?? "",
            sshUser: defaults.string(forKey: "sshUser") ?? "",
            useSshFallback: defaults.bool(forKey: "useSshFallback"),
            color: HostProfile.defaultColors[0],
            sharedFolderPath: defaults.string(forKey: "sharedFolderPath") ?? "~/Documents/Clawsy"
        )

        profiles = [profile]
        activeHostId = profile.id
        saveProfiles()
        os_log("Migrated legacy config to HostProfile: %{public}@", log: logger, type: .info, profile.name)
    }

    // MARK: - Host CRUD

    public func addHost(_ profile: HostProfile) {
        var newProfile = profile

        if newProfile.sharedFolderPath.isEmpty {
            let safeName = newProfile.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespaces)
            newProfile.sharedFolderPath = safeName.isEmpty
                ? "~/Documents/Clawsy"
                : "~/Documents/Clawsy/\(safeName)"
        }

        let resolved = newProfile.sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        try? FileManager.default.createDirectory(atPath: resolved, withIntermediateDirectories: true)

        profiles.append(newProfile)
        if profiles.count == 1 {
            activeHostId = newProfile.id
        }
        saveProfiles()
        os_log("Added host: %{public}@ (total: %d)", log: logger, type: .info, newProfile.name, profiles.count)
    }

    public func removeHost(id: UUID) {
        disconnectHost(id)
        connections.removeValue(forKey: id)
        handshakes.removeValue(forKey: id)
        commandRouters.removeValue(forKey: id)
        nodeConnections[id]?.disconnect()
        nodeConnections.removeValue(forKey: id)
        pollers.removeValue(forKey: id)
        perHostCancellables.removeValue(forKey: id)
        hostStates.removeValue(forKey: id)
        profiles.removeAll(where: { $0.id == id })

        if activeHostId == id {
            activeHostId = profiles.first?.id
            subscribeToActiveConnection()
        }
        saveProfiles()
    }

    public func updateHost(_ profile: HostProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let oldProfile = profiles[index]
        profiles[index] = profile
        saveProfiles()

        // React to node connection toggle change while connected
        if oldProfile.enableNodeConnection != profile.enableNodeConnection {
            if profile.enableNodeConnection {
                if connections[profile.id]?.isConnected == true {
                    startNodeConnection(for: profile.id)
                }
            } else {
                nodeConnections[profile.id]?.disconnect()
                nodeConnections.removeValue(forKey: profile.id)
                hostStates[profile.id]?.nodeConnected = false
            }
        }
    }

    public func switchActiveHost(to id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeHostId = id
        saveProfiles()
        subscribeToActiveConnection()
        os_log("Switched active host to: %{public}@", log: logger, type: .info, activeProfile?.name ?? "unknown")
    }

    // MARK: - Connection Lifecycle

    /// Connect all configured hosts
    public func connectAll() {
        for profile in profiles {
            connectHost(profile.id)
        }
        subscribeToActiveConnection()
    }

    /// Connect a single host. If already connected/connecting, disconnects first.
    public func connectHost(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }

        // Always start fresh — disconnect existing connection
        if let existing = connections[id] {
            existing.disconnect()
        }
        pollers[id]?.stop()

        let conn = ConnectionManager()
        connections[id] = conn

        // Create HandshakeManager with profile config
        let hsConfig = HandshakeManager.Config(
            gatewayToken: profile.serverToken,
            deviceToken: profile.deviceToken,
            displayName: "Clawsy (\(Host.current().localizedName ?? "Mac"))"
        )
        let hs = HandshakeManager(config: hsConfig)
        handshakes[id] = hs

        // Create CommandRouter
        let router = CommandRouter()
        commandRouters[id] = router

        // Create GatewayPoller — log to ConnectionManager's rawLog
        let poller = GatewayPoller()
        pollers[id] = poller
        poller.onLog = { [weak conn] msg in
            DispatchQueue.main.async { conn?.rawLog += "\n\(msg)" }
        }

        // Wire Poller → WebSocket (for sending envelopes via node.event)
        poller.onSendWebSocket = { [weak conn] frame in
            guard let data = try? JSONSerialization.data(withJSONObject: frame),
                  let text = String(data: data, encoding: .utf8) else { return }
            conn?.send(text)
        }

        // Wire agent responses → HostManager callback
        poller.onAgentResponse = { [weak self] agentName, message, sessionKey in
            self?.onAgentResponse?(agentName, message, sessionKey)
        }

        // Wire HandshakeManager ↔ ConnectionManager
        wireHandshake(hs, to: conn, profileId: id, poller: poller)

        // Wire CommandRouter ↔ ConnectionManager
        wireCommandRouter(router, to: conn, profileId: id)

        // Register platform-specific command handlers
        onRegisterHandlers?(router, id)

        // Build connection config from profile
        let connConfig = ConnectionConfig(
            gatewayHost: profile.gatewayHost,
            gatewayPort: profile.gatewayPort,
            serverToken: profile.serverToken,
            sshUser: profile.sshUser,
            useSshFallback: profile.useSshFallback,
            sshOnly: profile.sshOnly
        )

        // Initialize host state
        hostStates[id] = HostConnectionState()

        // Forward per-host connection state for host switcher dots
        perHostCancellables[id] = conn.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.hostStates[id]?.connectionState = newState
            }

        // Subscribe UI to this connection's state
        subscribeToActiveConnection()

        // Connect
        conn.connect(config: connConfig)
    }

    /// Disconnect a single host
    public func disconnectHost(_ id: UUID) {
        connections[id]?.disconnect()
        nodeConnections[id]?.disconnect()
        pollers[id]?.stop()
    }

    /// Disconnect all hosts
    public func disconnectAll() {
        for id in connections.keys {
            disconnectHost(id)
        }
    }

    /// Re-pair the active connection (clear device token, reconnect)
    public func repairActiveConnection() {
        guard let profile = activeProfile else { return }
        var updated = profile
        updated.deviceToken = nil
        updateHost(updated)

        if let id = activeHostId {
            disconnectHost(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.connectHost(id)
            }
        }
    }

    // MARK: - Node Connection

    /// Start the node connection for a host (second WebSocket with role=node).
    /// Must only be called when the operator connection is established.
    private func startNodeConnection(for hostId: UUID) {
        guard let profile = profiles.first(where: { $0.id == hostId }),
              profile.enableNodeConnection else { return }
        // Use stateMachine.state (synchronous) instead of @Published state (async)
        // to avoid race when called right after handleHandshakeComplete
        guard let conn = connections[hostId],
              conn.stateMachine.state.isConnected || conn.transport.isOpen else { return }

        // Build the WebSocket URL matching the operator connection
        let urlString: String
        #if os(macOS)
        if conn.sshTunnel.isRunning {
            urlString = "ws://127.0.0.1:\(conn.sshTunnel.localPort)"
        } else {
            let host = profile.gatewayHost
            let port = profile.gatewayPort
            let scheme = (host.contains("localhost") || host.contains("127.0.0.1")) ? "ws" : "wss"
            urlString = "\(scheme)://\(host):\(port)"
        }
        #else
        let host = profile.gatewayHost
        let port = profile.gatewayPort
        let scheme = (host.contains("localhost") || host.contains("127.0.0.1")) ? "ws" : "wss"
        urlString = "\(scheme)://\(host):\(port)"
        #endif

        guard let url = URL(string: urlString) else {
            os_log("[HostMgr] Invalid node WS URL: %{public}@", log: logger, type: .error, urlString)
            return
        }

        // Disconnect existing node connection if any
        nodeConnections[hostId]?.disconnect()

        let nodeConn = NodeConnectionManager()
        nodeConnections[hostId] = nodeConn

        // Forward logs to operator's rawLog
        nodeConn.onLog = { [weak conn] msg in
            DispatchQueue.main.async { conn?.rawLog += "\n\(msg)" }
        }

        // Register file command handlers
        nodeConn.onRegisterHandlers = { [weak self] router in
            self?.onRegisterNodeHandlers?(router, hostId)
        }

        // Handle reconnect requests
        nodeConn.onReconnectNeeded = { [weak self] in
            self?.startNodeConnection(for: hostId)
        }

        // Track node connection state
        nodeConn.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.hostStates[hostId]?.nodeConnected = connected
            }
            .store(in: &nodeCancellables)

        // Approval routing
        nodeConn.commandRouter.onApprovalRequired = { [weak self] command, params, completion in
            self?.onApprovalRequired?(hostId, command, params, completion)
        }

        // When using SSH tunnel, set Origin to match gateway's allowedOrigins
        let origin: String?
        #if os(macOS)
        if conn.sshTunnel.isRunning {
            let port = profile.gatewayPort.isEmpty ? "18789" : profile.gatewayPort
            origin = "http://localhost:\(port)"
        } else {
            origin = nil
        }
        #else
        origin = nil
        #endif

        nodeConn.connect(url: url, gatewayToken: profile.serverToken, deviceToken: profile.deviceToken, origin: origin)
        os_log("[HostMgr] Started node connection for %{public}@", log: logger, type: .info, profile.name)
    }

    // MARK: - Wiring

    private func wireHandshake(_ hs: HandshakeManager, to conn: ConnectionManager, profileId: UUID, poller: GatewayPoller) {
        // HandshakeManager sends messages via ConnectionManager
        hs.onSendMessage = { [weak conn] message in
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let text = String(data: data, encoding: .utf8) else { return }
            conn?.send(text)
        }

        // HandshakeManager reports results to ConnectionManager
        hs.onHandshakeComplete = { [weak self, weak conn, weak poller] result in
            // Store device token
            if let token = result.deviceToken, let self = self {
                if var profile = self.profiles.first(where: { $0.id == profileId }) {
                    profile.deviceToken = token
                    self.updateHost(profile)
                }
            }

            // Update host state
            DispatchQueue.main.async {
                self?.hostStates[profileId]?.gatewayVersion = result.serverVersion
                self?.hostStates[profileId]?.connId = result.connId
                self?.hostStates[profileId]?.pairingRequestId = nil
            }

            // Transition to .connected FIRST — startNodeConnection checks isConnected
            conn?.handleHandshakeComplete(deviceToken: result.deviceToken)

            // Start polling for agents/sessions now that we're connected
            poller?.start()

            // Send skill hint so the agent knows about Clawsy capabilities
            poller?.sendConnectedHint()

            // Start node connection if enabled (must be after handleHandshakeComplete)
            self?.startNodeConnection(for: profileId)
        }

        hs.onHandshakeFailed = { [weak conn] reason in
            conn?.handleHandshakeFailed(reason)
        }

        hs.onPairingRequired = { [weak self, weak conn] requestId in
            DispatchQueue.main.async {
                self?.hostStates[profileId]?.pairingRequestId = requestId
                if profileId == self?.activeHostId {
                    self?.pairingRequestId = requestId
                }
            }
            conn?.handlePairingRequired(requestId: requestId)
        }

        // ConnectionManager forwards messages to HandshakeManager during handshake
        let existingOnConnected = conn.onConnected
        conn.onConnected = { [weak hs] in
            existingOnConnected?()
            // Handshake starts when WS connects — messages route through processMessage
        }

        // Route incoming messages: handshake → poller → command router
        conn.onMessage = { [weak hs, weak self, weak poller] text in
            // Try handshake first
            if hs?.processMessage(text) == true { return }
            // Then try poller (responses to agent/status/chat.send requests)
            if poller?.processMessage(text) == true { return }
            // Then try command router (node.invoke.request)
            if let router = self?.commandRouters[profileId],
               router.processMessage(text) { return }
            // Unhandled messages (tick events, etc.)
        }
    }

    private func wireCommandRouter(_ router: CommandRouter, to conn: ConnectionManager, profileId: UUID) {
        // Router sends responses via ConnectionManager
        router.onSendMessage = { [weak conn] message in
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let text = String(data: data, encoding: .utf8) else { return }
            conn?.send(text)
        }

        // Router delegates approval to the HostManager's callback
        router.onApprovalRequired = { [weak self] command, params, completion in
            self?.onApprovalRequired?(profileId, command, params, completion)
        }
    }

    // MARK: - Active Host Subscription

    private func subscribeToActiveConnection() {
        activeCancellables.removeAll()

        guard let id = activeHostId ?? profiles.first?.id,
              let conn = connections[id] else {
            state = .disconnected
            failure = nil
            retryCountdown = 0
            pairingRequestId = nil
            rawLog = ""
            return
        }

        conn.$state.receive(on: DispatchQueue.main)
            .assign(to: \.state, on: self)
            .store(in: &activeCancellables)

        conn.$connectionFailure.receive(on: DispatchQueue.main)
            .assign(to: \.failure, on: self)
            .store(in: &activeCancellables)

        conn.$retryCountdown.receive(on: DispatchQueue.main)
            .assign(to: \.retryCountdown, on: self)
            .store(in: &activeCancellables)

        conn.$rawLog.receive(on: DispatchQueue.main)
            .assign(to: \.rawLog, on: self)
            .store(in: &activeCancellables)
    }

    // MARK: - Send via Active Connection

    /// Send a text message through the active connection
    @discardableResult
    public func send(_ text: String) -> Bool {
        activeConnection?.send(text) ?? false
    }

    /// Send a JSON dictionary through the active connection
    @discardableResult
    public func sendJSON(_ dict: [String: Any]) -> Bool {
        activeConnection?.sendJSON(dict) ?? false
    }

    /// Gateway base URL for the active connection (for REST API calls)
    public var activeGatewayBaseURL: String? {
        activeConnection?.gatewayBaseURL
    }

    // MARK: - Multi-Host Folder Migration

    public func checkMigrationNeeded() -> (HostProfile, String)? {
        guard profiles.count == 1, let first = profiles.first else { return nil }
        if !first.sharedFolderPath.hasPrefix("~/Clawsy/") {
            return (first, first.sharedFolderPath)
        }
        return nil
    }

    public func migrateFirstHostFolder(to newPath: String) {
        guard var first = profiles.first else { return }
        let oldResolved = first.sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let newResolved = newPath.replacingOccurrences(of: "~", with: NSHomeDirectory())

        try? FileManager.default.createDirectory(atPath: newResolved, withIntermediateDirectories: true)

        if let contents = try? FileManager.default.contentsOfDirectory(atPath: oldResolved) {
            for item in contents {
                let src = (oldResolved as NSString).appendingPathComponent(item)
                let dst = (newResolved as NSString).appendingPathComponent(item)
                try? FileManager.default.moveItem(atPath: src, toPath: dst)
            }
        }

        first.sharedFolderPath = newPath
        updateHost(first)
        os_log("Migrated first host folder: %{public}@ → %{public}@", log: logger, type: .info, oldResolved, newResolved)
    }
}
