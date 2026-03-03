import Foundation
import Combine
import os.log

/// Manages multiple host profiles and their NetworkManager connections.
/// One NetworkManager per host, all connected simultaneously.
/// Outbound actions route through the active host only.
public class HostManager: ObservableObject {
    private let logger = OSLog(subsystem: "ai.clawsy", category: "HostManager")

    @Published public var profiles: [HostProfile] = []
    @Published public var activeHostId: UUID?

    // MARK: - Forwarded NetworkManager state (observed by SwiftUI via HostManager)
    @Published public var isConnected: Bool = false
    @Published public var connectionStatus: String = "STATUS_DISCONNECTED"
    @Published public var connectionAttemptCount: Int = 0
    @Published public var connectionError: ConnectionError? = nil
    @Published public var isServerClawsyAware: Bool = false

    private var activeCancellables = Set<AnyCancellable>()

    /// One NetworkManager per host, keyed by profile UUID
    public var networkManagers: [UUID: NetworkManager] = [:]

    /// The currently active profile (convenience)
    public var activeProfile: HostProfile? {
        guard let id = activeHostId else { return profiles.first }
        return profiles.first(where: { $0.id == id })
    }

    /// The currently active NetworkManager
    public var activeNetworkManager: NetworkManager? {
        guard let id = activeHostId ?? profiles.first?.id else { return nil }
        return networkManagers[id]
    }

    /// Subscribe to the active NM's published properties so HostManager
    /// re-publishes them → SwiftUI re-renders ContentView automatically.
    public func subscribeToActiveNM() {
        activeCancellables.removeAll()
        guard let nm = activeNetworkManager else {
            isConnected = false
            connectionStatus = "STATUS_DISCONNECTED"
            connectionAttemptCount = 0
            connectionError = nil
            isServerClawsyAware = false
            return
        }
        nm.$isConnected.receive(on: DispatchQueue.main)
            .assign(to: \.isConnected, on: self).store(in: &activeCancellables)
        nm.$connectionStatus.receive(on: DispatchQueue.main)
            .assign(to: \.connectionStatus, on: self).store(in: &activeCancellables)
        nm.$connectionAttemptCount.receive(on: DispatchQueue.main)
            .assign(to: \.connectionAttemptCount, on: self).store(in: &activeCancellables)
        nm.$connectionError.receive(on: DispatchQueue.main)
            .assign(to: \.connectionError, on: self).store(in: &activeCancellables)
        nm.$isServerClawsyAware.receive(on: DispatchQueue.main)
            .assign(to: \.isServerClawsyAware, on: self).store(in: &activeCancellables)
    }

    public init() {
        loadProfiles()
        migrateFromLegacyIfNeeded()
    }

    // MARK: - Persistence

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
        // Ensure activeHostId points to an existing profile
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

        // Also keep legacy keys in sync for backward compatibility (FinderSync, Share Extension)
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

    /// If no hostProfiles exist but legacy keys do, create a first profile silently.
    private func migrateFromLegacyIfNeeded() {
        guard profiles.isEmpty else { return }
        let defaults = SharedConfig.sharedDefaults
        guard let legacyHost = defaults.string(forKey: "serverHost"), !legacyHost.isEmpty else { return }

        let legacyPort = defaults.string(forKey: "serverPort") ?? "18789"
        let legacyToken = defaults.string(forKey: "serverToken") ?? ""
        let legacySshUser = defaults.string(forKey: "sshUser") ?? ""
        let legacyFallback: Bool = {
            if defaults.object(forKey: "useSshFallback") == nil { return true }
            return defaults.bool(forKey: "useSshFallback")
        }()
        let legacyFolder = defaults.string(forKey: "sharedFolderPath") ?? "~/Documents/Clawsy"

        let profile = HostProfile(
            name: legacyHost,
            gatewayHost: legacyHost,
            gatewayPort: legacyPort,
            serverToken: legacyToken,
            sshUser: legacySshUser,
            useSshFallback: legacyFallback,
            color: HostProfile.defaultColors[0],
            sharedFolderPath: legacyFolder
        )

        profiles = [profile]
        activeHostId = profile.id
        saveProfiles()
        os_log("Migrated legacy config to first HostProfile: %{public}@", log: logger, type: .info, profile.name)
    }

    // MARK: - Host Management

    public func switchActiveHost(to id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeHostId = id
        saveProfiles()
        subscribeToActiveNM()
        os_log("Switched active host to: %{public}@", log: logger, type: .info, activeProfile?.name ?? "unknown")
    }

    /// Add a new host profile. Returns a migration info tuple if migration is needed for the 2nd host.
    /// The caller (UI) should handle migration dialogs.
    public func addHost(_ profile: HostProfile) {
        var newProfile = profile

        // Auto-create shared folder if empty
        if newProfile.sharedFolderPath.isEmpty {
            let safeName = newProfile.name.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            newProfile.sharedFolderPath = "~/Clawsy/\(safeName)"
        }

        // Ensure the folder exists
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
        // Disconnect and remove the NetworkManager
        if let nm = networkManagers[id] {
            nm.disconnect()
            networkManagers.removeValue(forKey: id)
        }
        profiles.removeAll(where: { $0.id == id })

        // If we removed the active host, switch to the first remaining
        if activeHostId == id {
            activeHostId = profiles.first?.id
        }
        saveProfiles()
    }

    public func updateHost(_ profile: HostProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        saveProfiles()
    }

    // MARK: - Connection Management

    /// Create and connect NetworkManagers for all profiles
    public func connectAll(setupCallbacks: @escaping (NetworkManager, HostProfile) -> Void) {
        for profile in profiles {
            let nm: NetworkManager
            if let existing = networkManagers[profile.id] {
                nm = existing
            } else {
                nm = NetworkManager(hostProfile: profile)
                networkManagers[profile.id] = nm
            }
            setupCallbacks(nm, profile)
            nm.configure(
                host: profile.gatewayHost,
                port: profile.gatewayPort,
                token: profile.serverToken,
                sshUser: profile.sshUser,
                fallback: profile.useSshFallback
            )
            nm.connect()
        }
        subscribeToActiveNM()
    }

    /// Disconnect all NetworkManagers
    public func disconnectAll() {
        for (_, nm) in networkManagers {
            nm.disconnect()
        }
    }

    /// Connect a specific host
    public func connectHost(_ id: UUID, setupCallbacks: @escaping (NetworkManager, HostProfile) -> Void) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        let nm: NetworkManager
        if let existing = networkManagers[id] {
            nm = existing
        } else {
            nm = NetworkManager(hostProfile: profile)
            networkManagers[id] = nm
        }
        setupCallbacks(nm, profile)
        nm.configure(
            host: profile.gatewayHost,
            port: profile.gatewayPort,
            token: profile.serverToken,
            sshUser: profile.sshUser,
            fallback: profile.useSshFallback
        )
        nm.connect()
    }

    /// Disconnect a specific host
    public func disconnectHost(_ id: UUID) {
        networkManagers[id]?.disconnect()
    }

    /// Check if adding a 2nd host requires folder migration
    /// Returns (firstProfile, oldPath) if migration is needed, nil otherwise
    public func checkMigrationNeeded() -> (HostProfile, String)? {
        guard profiles.count == 1, let first = profiles.first else { return nil }
        let defaultNewPath = "~/Clawsy/\(first.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-"))"
        // If the first host uses a non-standard path (not under ~/Clawsy/), migration is needed
        if !first.sharedFolderPath.hasPrefix("~/Clawsy/") {
            return (first, first.sharedFolderPath)
        }
        return nil
    }

    /// Perform folder migration for the first host when adding a second
    public func migrateFirstHostFolder(to newPath: String) {
        guard var first = profiles.first else { return }
        let oldResolved = first.sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let newResolved = newPath.replacingOccurrences(of: "~", with: NSHomeDirectory())

        // Create new directory
        try? FileManager.default.createDirectory(atPath: newResolved, withIntermediateDirectories: true)

        // Move files from old to new
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: oldResolved) {
            for item in contents {
                let src = (oldResolved as NSString).appendingPathComponent(item)
                let dst = (newResolved as NSString).appendingPathComponent(item)
                try? FileManager.default.moveItem(atPath: src, toPath: dst)
            }
        }

        // Update profile
        first.sharedFolderPath = newPath
        updateHost(first)
        os_log("Migrated first host folder from %{public}@ to %{public}@", log: logger, type: .info, oldResolved, newResolved)
    }
}
