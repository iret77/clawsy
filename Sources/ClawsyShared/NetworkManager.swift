import Foundation
import Starscream
import CryptoKit
import SwiftUI
import UserNotifications
import os.log
import IOKit.ps

#if canImport(Network)
import Network
#endif

#if canImport(AppKit)
import AppKit
import ApplicationServices  // AXIsProcessTrusted()
typealias ClawsyImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias ClawsyImage = UIImage
#endif

// MARK: - GatewaySession Model

public struct GatewaySession: Identifiable, Equatable {
    public let id: String        // session key
    public let label: String?
    public let kind: String
    public let status: String    // "running", "done", "error"
    public let model: String?
    public let startedAt: Date?
    public let task: String?
}

// MARK: - DisconnectReason

/// Classifies why the WebSocket connection was terminated.
/// Only `.connectionLost` triggers automatic reconnect with backoff.
public enum DisconnectReason: Equatable {
    /// Connection was active (handshake complete) and dropped unexpectedly.
    case connectionLost
    /// User explicitly tapped the Disconnect button or removed the host.
    case userInitiated
    /// Connection setup failed before the session became active (pre-hello-ok).
    case setupFailed(String)
}

// MARK: - NetworkManager (Native Node Protocol)

public class NetworkManager: NSObject, ObservableObject, WebSocketDelegate, UNUserNotificationCenterDelegate {
    private let logger = OSLog(subsystem: "ai.clawsy", category: "Network")
    
    @Published public var isConnected = false
    @Published public var isHandshakeComplete = false 
    @Published public var connectionStatus = "STATUS_DISCONNECTED"
    @Published public var connectionAttemptCount = 0
    @Published public var lastMessage = ""
    @Published public var rawLog = ""
    @Published public var isServerClawsyAware = false
    @Published public var serverVersion = "unknown"
    @Published public var connectionError: ConnectionError?
    @Published public var gatewaySessions: [GatewaySession] = []
    @Published public var pairingRequestId: String = ""  // Request ID for manual pairing approval
    @Published public var retryCountdown: Int = 0  // Seconds until next retry (0 = no retry pending)
    @Published public var serverDetected: Bool = false
    @Published public var serverSetupNeeded: Bool = false
    private var retryTimer: Timer?
    private var retryAttempt: Int = 0
    private let baseRetryDelay: TimeInterval = 2.0
    private let maxRetryDelay: TimeInterval = 60.0  // Cap at 60 seconds
    
    /// Tracks the reason for the most recent disconnection.
    /// Reconnect logic only fires when this is `.connectionLost`.
    private var disconnectReason: DisconnectReason?
    
    /// Tracks whether a handshake was ever completed in this connection lifecycle.
    /// Set to `true` on `hello-ok`, cleared only on user-initiated `disconnect()`.
    /// Used to distinguish "reconnect after gateway restart" from "first-time setup failure":
    /// when `true`, pre-handshake failures during reconnect are treated as `.connectionLost`
    /// (retry) instead of `.setupFailed` (give up).
    private var wasEverConnected = false
    
    // Mood Tracking State
    private static var lastAppSwitchTime = Date()
    private static var appSwitchCount = 0
    private static var lastAppName = ""
    
    private var socket: WebSocket?
    private var connectionWatchdog: Timer?
    private var pairingTimeoutTimer: Timer?
    private var isPairing = false
    private var signingKey: Curve25519.Signing.PrivateKey?
    private var publicKey: Curve25519.Signing.PublicKey?

    // Gateway Sessions Polling
    private var sessionsPollerTimer: Timer?
    private var pendingSessionsListReqId: String?
    private let sessionsPollerInterval: TimeInterval = 10
    private let sessionsActiveWindowSeconds: TimeInterval = 300  // 5 min = "running"
    
    // SSH Tunnel Management (macOS only)
    #if os(macOS)
    private var sshProcess: Process?
    #endif
    private var isUsingSshTunnel = false
    
    // Callbacks for UI/Logic
    public var onHandshakeComplete: (() -> Void)?
    public var onScreenshotRequested: ((Bool, Any) -> Void)?
    public var onClipboardReadRequested: ((Any) -> Void)?
    public var onClipboardWriteRequested: ((String, Any) -> Void)?
    public var onFileSyncRequested: ((String, String, @escaping (TimeInterval?) -> Void, @escaping () -> Void) -> Void)?
    public var onCameraPreviewRequested: ((NSImage, @escaping () -> Void, @escaping () -> Void) -> Void)?
    
    // Location Support
    private let locationManager = LocationManager()
    
    // Permission Tracking
    private var filePermissionExpiry: Date?
    
    // Host Profile — if set, use profile settings instead of SharedConfig globals
    public var hostProfile: HostProfile?
    
    /// The UUID of the associated host profile (for HostManager lookups)
    public var hostProfileId: UUID? { hostProfile?.id }
    
    // Internal Sync'd Settings — now profile-aware
    private var serverHost: String {
        hostProfile?.gatewayHost ?? SharedConfig.serverHost
    }
    private var serverPort: String {
        hostProfile?.gatewayPort ?? SharedConfig.serverPort
    }
    private var serverToken: String {
        hostProfile?.serverToken ?? SharedConfig.serverToken
    }
    private var sshUser: String {
        hostProfile?.sshUser ?? (SharedConfig.sharedDefaults.string(forKey: "sshUser") ?? "")
    }
    private var useSshFallback: Bool {
        if let profile = hostProfile { return profile.useSshFallback }
        if SharedConfig.sharedDefaults.object(forKey: "useSshFallback") == nil { return true }
        return SharedConfig.sharedDefaults.bool(forKey: "useSshFallback")
    }
    private var sshOnly: Bool {
        hostProfile?.sshOnly ?? false
    }
    private var sharedFolderPath: String {
        hostProfile?.sharedFolderPath ?? (SharedConfig.sharedDefaults.string(forKey: "sharedFolderPath") ?? "~/Documents/Clawsy")
    }
    
    /// Whether to include telemetry in envelopes — per-host when profile exists, global fallback otherwise.
    public var extendedContextEnabled: Bool {
        hostProfile?.extendedContextEnabled ?? SharedConfig.extendedContextEnabled
    }
    
    // Device token for node pairing (per-host)
    private var deviceTokenKey: String { "clawsy_device_token_\(serverHost)" }
    private var deviceToken: String? {
        get {
            // Check hostProfile first
            if let dt = hostProfile?.deviceToken { return dt }
            return SharedConfig.sharedDefaults.string(forKey: deviceTokenKey)
        }
        set {
            if let val = newValue {
                SharedConfig.sharedDefaults.set(val, forKey: deviceTokenKey)
            } else {
                SharedConfig.sharedDefaults.removeObject(forKey: deviceTokenKey)
            }
            // Also update the profile in memory
            hostProfile?.deviceToken = newValue
            SharedConfig.sharedDefaults.synchronize()
        }
    }
    
    /// Initialize with a HostProfile (multi-host mode)
    public init(hostProfile: HostProfile) {
        self.hostProfile = hostProfile
        super.init()
        loadOrGenerateSigningKey()
        setupNotifications()
        setupLocation()
    }
    
    /// Legacy init (single-host mode, reads from SharedConfig)
    public override init() {
        super.init()
        loadOrGenerateSigningKey()
        setupNotifications()
        setupLocation()
    }
    
    /// Returns the UserDefaults key for this host's signing key.
    /// Per-host mode uses `nodePrivateKey_<gatewayHost>_<gatewayPort>`;
    /// legacy single-host mode (no hostProfile) keeps `nodePrivateKey` for backward compatibility.
    private var signingKeyDefaultsKey: String {
        if let profile = hostProfile {
            return "nodePrivateKey_\(profile.gatewayHost)_\(profile.gatewayPort)"
        }
        return "nodePrivateKey"
    }

    private func loadOrGenerateSigningKey() {
        let keyName = signingKeyDefaultsKey

        // Try to load existing per-host key
        if let savedKeyData = SharedConfig.sharedDefaults.data(forKey: keyName),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: savedKeyData) {
            self.signingKey = key
        } else {
            // For per-host mode, try migrating the legacy shared key on first run
            if hostProfile != nil,
               let legacyData = SharedConfig.sharedDefaults.data(forKey: "nodePrivateKey"),
               let legacyKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: legacyData) {
                // Don't migrate — generate a fresh key so each host gets a distinct identity
                let _ = legacyKey // suppress unused warning
            }
            let newKey = Curve25519.Signing.PrivateKey()
            self.signingKey = newKey
            SharedConfig.sharedDefaults.set(newKey.rawRepresentation, forKey: keyName)
        }
        self.publicKey = self.signingKey?.publicKey
    }
    
    private func setupLocation() {
        locationManager.onLocationUpdate = { [weak self] location in
            self?.sendEvent(kind: "location", payload: location)
        }
    }
    
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        let revokeAction = UNNotificationAction(identifier: "REVOKE_PERMISSION",
                                              title: NSLocalizedString("REVOKE_PERMISSION", bundle: .clawsy, comment: ""),
                                              options: [.destructive])
        
        let category = UNNotificationCategory(identifier: "FILE_SYNC",
                                             actions: [revokeAction],
                                             intentIdentifiers: [],
                                             options: [])
        
        center.setNotificationCategories([category])
        
        center.requestAuthorization(options: [.alert, .sound]) { granted, err in
            if let err = err {
                os_log("Notification permission error: %{public}@", log: self.logger, type: .error, err.localizedDescription)
            }
        }
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                didReceive response: UNNotificationResponse, 
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "REVOKE_PERMISSION" {
            os_log("User revoked file permissions via notification", log: logger, type: .info)
            filePermissionExpiry = nil
        }
        completionHandler()
    }
    
    private func notifyAction(title: String, body: String, isAuto: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        if isAuto {
            content.categoryIdentifier = "FILE_SYNC"
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    public func configure(host: String, port: String, token: String, sshUser: String? = nil, fallback: Bool? = nil) {
        // Only write to SharedConfig globals in legacy (no hostProfile) mode.
        // In multi-host mode the HostProfile is the source of truth; writing
        // globals here would let the last-connected host overwrite the active
        // host's values, breaking FinderSync / Share extension reads.
        if hostProfile == nil {
            SharedConfig.save(host: host, port: port, token: token)
            if let user = sshUser { SharedConfig.sharedDefaults.set(user, forKey: "sshUser") }
            if let fback = fallback { SharedConfig.sharedDefaults.set(fback, forKey: "useSshFallback") }
            SharedConfig.sharedDefaults.synchronize()
        }
        os_log("Configured with Host: %{public}@, Port: %{public}@", log: logger, type: .info, host, port)
    }

    public func connect() {
        SharedConfig.sharedDefaults.synchronize()
        
        // Reset log only for the very first attempt in a connection cycle.
        // Important: SSH fallback may call connect() again; keep logs so we can debug tunnel startup.
        if connectionAttemptCount == 0 || self.rawLog.isEmpty {
            let dateStr = ISO8601DateFormatter().string(from: Date())
            self.rawLog = "[LOG START] \(dateStr) | Clawsy \(SharedConfig.versionDisplay)\n----------------------------------------\n"
        }
        
        // SSH-Only Mode: skip WSS entirely, go straight to SSH tunnel
        #if os(macOS)
        if sshOnly && !sshUser.isEmpty && !isUsingSshTunnel {
            rawLog += "\n[SSH] SSH-Only mode — skipping direct WSS connection"
            connectionAttemptCount += 1
            DispatchQueue.main.async {
                self.connectionStatus = "STATUS_STARTING_SSH"
            }
            startSshTunnel()
            return
        }
        #endif
        
        let host = serverHost
        let token = serverToken
        
        guard !host.isEmpty, !token.isEmpty else {
            DispatchQueue.main.async {
                self.connectionStatus = "STATUS_DISCONNECTED"
                self.rawLog += "\n[WSS] Error: Missing Host or Token"
            }
            return
        }
        
        if connectionAttemptCount == 0 {
            retryAttempt = 0
            retryCountdown = 0
            retryTimer?.invalidate()
            retryTimer = nil
            isUsingSshTunnel = false
            // Only clear disconnectReason on truly fresh connections (never connected before).
            // During reconnect cycles (wasEverConnected=true), keep .connectionLost so that
            // pre-handshake failures don't get misclassified as .setupFailed.
            if !wasEverConnected {
                disconnectReason = nil
            }
        }
        
        connectionAttemptCount += 1
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "STATUS_CONNECTING"
        }
        
        socket?.delegate = nil
        socket?.disconnect()
        socket = nil
        
        var targetUrlStr: String
        if isUsingSshTunnel {
            targetUrlStr = "ws://127.0.0.1:\(sshTunnelLocalPort)"
        } else {
            let scheme = (host.contains("localhost") || host.contains("127.0.0.1")) ? "ws" : "wss"
            targetUrlStr = "\(scheme)://\(host):\(serverPort)"
        }

        guard let targetUrl = URL(string: targetUrlStr) else {
            DispatchQueue.main.async {
                self.connectionStatus = "STATUS_ERROR"
                self.rawLog += "\n[WSS] Error: Invalid URL \(targetUrlStr)"
            }
            return
        }
        
        attemptConnection(to: targetUrl)
    }

    private func attemptConnection(to url: URL) {
        connectionWatchdog?.invalidate()

        // SSH tunnel startup + first WS connect can legitimately take longer than 5s.
        // Treat the watchdog as an overall connect budget.
        let watchdogSeconds: TimeInterval = self.isUsingSshTunnel ? 12.0 : 8.0

        rawLog += "\n[WSS] Connecting to \(url.absoluteString) (watchdog: \(Int(watchdogSeconds))s)"

        connectionWatchdog = Timer.scheduledTimer(withTimeInterval: watchdogSeconds, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConnected, !self.isPairing else { return }
            DispatchQueue.main.async {
                self.rawLog += "\n[WSS] Watchdog Timeout (\(Int(watchdogSeconds))s)"
                self.handleConnectionFailure(err: NSError(domain: "ai.clawsy", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection Timeout (Watchdog)"]))
            }
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = watchdogSeconds

        let newSocket = WebSocket(request: request)
        newSocket.delegate = self
        self.socket = newSocket
        self.socket?.connect()
    }
    
    private func scheduleRetry() {
        // Only reconnect when the connection was lost unexpectedly.
        // User-initiated disconnects and setup failures must NOT trigger retry.
        if let reason = disconnectReason, reason != .connectionLost {
            rawLog += "\n[RECONNECT] Skipping retry — disconnect reason: \(reason)"
            return
        }
        
        // Prevent double-schedule: if a timer is already running, don't create another one
        if let existing = retryTimer, existing.isValid {
            rawLog += "\n[RECONNECT] scheduleRetry called but timer already running — ignoring"
            return
        }

        let delay = min(baseRetryDelay * pow(2.0, Double(retryAttempt)), maxRetryDelay)
        let jitter = Double.random(in: 0...1.0)
        let actualDelay = delay + jitter
        let delayInt = max(Int(actualDelay.rounded(.up)), 1)
        retryAttempt += 1
        retryCountdown = delayInt
        rawLog += "\n[RECONNECT] Attempt \(retryAttempt) in \(String(format: "%.1f", actualDelay))s"
        connectionStatus = "STATUS_RECONNECT_WAITING"

        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.retryCountdown -= 1
            rawLog += "\n[TIMER] countdown=\(self.retryCountdown)"
            if self.retryCountdown <= 0 {
                timer.invalidate()
                self.retryTimer = nil
                self.isUsingSshTunnel = false
                self.connect()
            }
        }
    }

    private func handleConnectionFailure(err: Error?) {
        DispatchQueue.main.async {
            self.connectionWatchdog?.invalidate()
            self.connectionWatchdog = nil
            
            self.socket?.delegate = nil
            self.socket?.disconnect()
            self.socket = nil

            #if os(macOS)
            if self.useSshFallback && !self.isUsingSshTunnel && !self.sshUser.isEmpty && !self.wasEverConnected {
                // First-time failure: try SSH tunnel as part of the initial setup path.
                // Don't set setupFailed yet — SSH fallback is still "attempting to connect".
                // If SSH also fails, the SSH failure path sets .setupFailed explicitly.
                // Skip SSH fallback during reconnect (wasEverConnected=true) — direct WSS worked before.
                self.startSshTunnel()
            } else {
                // Classify the failure:
                // - wasEverConnected=true → this is a reconnect attempt, keep as .connectionLost
                // - wasEverConnected=false → genuine first-time setup failure
                if !self.isHandshakeComplete && self.disconnectReason == nil {
                    if self.wasEverConnected {
                        self.disconnectReason = .connectionLost
                        self.rawLog += "\n[RECONNECT] Pre-handshake failure during reconnect — treating as connectionLost"
                    } else {
                        let detail = err?.localizedDescription ?? "Connection failed before handshake"
                        self.disconnectReason = .setupFailed(detail)
                    }
                }
                self.runDiagnostics(err: err)
                self.scheduleRetry()
            }
            #else
            if !self.isHandshakeComplete && self.disconnectReason == nil {
                if self.wasEverConnected {
                    self.disconnectReason = .connectionLost
                    self.rawLog += "\n[RECONNECT] Pre-handshake failure during reconnect — treating as connectionLost"
                } else {
                    let detail = err?.localizedDescription ?? "Connection failed before handshake"
                    self.disconnectReason = .setupFailed(detail)
                }
            }
            self.runDiagnostics(err: err)
            self.scheduleRetry()
            #endif
        }
    }
    
    #if os(macOS)
    private var sshTunnelLocalPort: UInt16 = 18790

    /// Finds a free TCP port on localhost by binding to port 0.
    /// Returns the assigned port number, or nil on failure.
    /// Returns true if a TCP connection to host:port can be established within ~400ms.
    private func isTcpPortOpen(host: String, port: UInt16) -> Bool {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }

        // Set send/receive timeout so connect() doesn't block indefinitely
        var tv = timeval(tv_sec: 0, tv_usec: 400_000)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func findFreePort() -> UInt16? {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        var assignedAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &assignedAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(sock, $0, &len)
            }
        }
        guard got == 0 else { return nil }
        return UInt16(bigEndian: assignedAddr.sin_port)
    }

    private func sshKeyPathIfAvailable() -> String? {
        // Key import was removed — SSH uses ~/.ssh/ defaults automatically.
        // Clean up any leftover phantom key files from old versions.
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroup) {
            let keyURL = groupURL.appendingPathComponent("clawsy_ssh_key")
            if FileManager.default.fileExists(atPath: keyURL.path) {
                try? FileManager.default.removeItem(at: keyURL)
            }
        }
        return nil
    }

    private func parseSshHostAndPort(_ host: String) -> (host: String, port: String?) {
        // Accept "example.com:2222" (common) — best effort. IPv6 users should omit ":port".
        let parts = host.split(separator: ":")
        if parts.count == 2, let p = Int(parts[1]), p > 0 && p < 65536 {
            return (String(parts[0]), String(p))
        }
        return (host, nil)
    }

    private func startSshTunnel() {
        let hostRaw = self.serverHost
        let user = self.sshUser
        let port = self.serverPort

        guard !user.isEmpty else {
            DispatchQueue.main.async { self.connectionStatus = "STATUS_SSH_USER_MISSING" }
            return
        }

        DispatchQueue.main.async {
            self.connectionStatus = "STATUS_STARTING_SSH"
            self.rawLog += "\n[SSH] Starting ssh tunnel process…"
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // --- Bug fix: clean up previous SSH process and free port 18790 ---
            if let prev = self.sshProcess {
                // SIGKILL — immediate, no graceful shutdown, port released instantly
                kill(prev.processIdentifier, SIGKILL)
                prev.waitUntilExit()
                self.sshProcess = nil
            }
            
            // Also kill any leftover SSH process from a previous Clawsy session
            // holding the tunnel port (lsof works for our own processes in sandbox)
            let killPortProc = Process()
            killPortProc.executableURL = URL(fileURLWithPath: "/bin/sh")
            killPortProc.arguments = ["-c", "lsof -ti tcp:\(self.sshTunnelLocalPort) 2>/dev/null | xargs kill -9 2>/dev/null; true"]
            killPortProc.standardOutput = FileHandle.nullDevice
            killPortProc.standardError = FileHandle.nullDevice
            try? killPortProc.run()
            killPortProc.waitUntilExit()
            
            // Give the OS time to release the port
            Thread.sleep(forTimeInterval: 1.5)
            // --- End port cleanup ---

            // Find a free local port for this tunnel session
            if let freePort = self.findFreePort() {
                self.sshTunnelLocalPort = freePort
                DispatchQueue.main.async {
                    self.rawLog += "\n[SSH] Using dynamic local port: \(freePort)"
                }
            }

            let (host, sshPortString) = self.parseSshHostAndPort(hostRaw)
            let sshPort = sshPortString ?? "22"
            let targetPort = port.isEmpty ? "18789" : port
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            
            // Build SSH arguments.
            // If the user imported an SSH key (stored in the app group container),
            // pass it via -i so SSH uses it. Do NOT add IdentitiesOnly=yes — that
            // would block ssh-agent fallback when no imported key is present.
            var args = ["-NT"]
            
            if let keyPath = self.sshKeyPathIfAvailable() {
                args += ["-i", keyPath]
                DispatchQueue.main.async {
                    self.rawLog += "\n[SSH] Using imported key: \(keyPath)"
                }
            } else {
                DispatchQueue.main.async {
                    self.rawLog += "\n[SSH] No imported key — using ~/.ssh/ defaults"
                }
            }
            
            args += [
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=10",
                "-o", "ServerAliveInterval=15",
                "-o", "ServerAliveCountMax=3",
                "-o", "ExitOnForwardFailure=yes",
                "-p", sshPort,
                "-L", "127.0.0.1:\(self.sshTunnelLocalPort):127.0.0.1:\(targetPort)",
                "\(user)@\(host)"
            ]
            
            process.arguments = args
            
            // Capture stderr for diagnostics
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = FileHandle.nullDevice
            
            do {
                try process.run()
                self.sshProcess = process

                // Poll until the tunnel port is actually accepting connections (max 20s)
                let tunnelPort = self.sshTunnelLocalPort
                var tunnelReady = false
                let deadline = Date().addingTimeInterval(20.0)
                while Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.5)
                    guard process.isRunning else { break }
                    if self.isTcpPortOpen(host: "127.0.0.1", port: tunnelPort) {
                        tunnelReady = true
                        break
                    }
                }

                if tunnelReady {
                    DispatchQueue.main.async {
                        self.rawLog += "\n[SSH] Tunnel ready on 127.0.0.1:\(tunnelPort)"
                        self.isUsingSshTunnel = true
                        self.disconnectReason = nil  // SSH succeeded — clear any prior setup failure
                        self.connect()
                    }
                } else {
                    let errData = errorPipe.fileHandleForReading.availableData
                    let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    DispatchQueue.main.async {
                        let reason = process.isRunning ? "Port never opened (timeout 20s)" : "Process exited (code \(process.terminationStatus)): \(errStr)"
                        self.rawLog += "\n[SSH] Tunnel failed: \(reason)"
                        self.connectionStatus = "STATUS_SSH_FAILED"
                        self.isUsingSshTunnel = false
                        self.connectionError = .sshTunnelFailed
                        // During reconnect, keep as connectionLost to allow further retries
                        if self.wasEverConnected {
                            self.disconnectReason = .connectionLost
                        } else {
                            self.disconnectReason = .setupFailed("SSH tunnel: \(reason)")
                        }
                        self.scheduleRetry()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.rawLog += "\n[SSH] Failed to start: \(error.localizedDescription)"
                    self.connectionStatus = "STATUS_SSH_FAILED"
                    self.isUsingSshTunnel = false
                    self.connectionError = .sshTunnelFailed
                    // During reconnect, keep as connectionLost to allow further retries
                    if self.wasEverConnected {
                        self.disconnectReason = .connectionLost
                    } else {
                        self.disconnectReason = .setupFailed("SSH: \(error.localizedDescription)")
                    }
                    self.scheduleRetry()
                }
            }
        }
    }
    #endif
    
    private func runDiagnostics(err: Error?) {
        let errorDesc = err?.localizedDescription ?? "Unknown error"
        if errorDesc.contains("refused") {
            connectionStatus = "STATUS_OFFLINE_REFUSED"
        } else if errorDesc.contains("timed out") {
            connectionStatus = "STATUS_OFFLINE_TIMEOUT"
        } else {
            connectionStatus = "STATUS_ERROR"
        }
        // Classify the error for user-facing banner
        let sshConfigured = !sshUser.isEmpty && useSshFallback
        if let classified = ConnectionError.classify(connectionStatus: connectionStatus, usingSshTunnel: isUsingSshTunnel, sshConfigured: sshConfigured) {
            connectionError = classified
        }
    }
    
    public func disconnect() {
        disconnectReason = .userInitiated
        wasEverConnected = false  // User-initiated disconnect resets the lifecycle
        
        isPairing = false
        pairingRequestId = ""
        pairingTimeoutTimer?.invalidate()
        pairingTimeoutTimer = nil

        stopSessionsPoller()
        
        socket?.delegate = nil
        socket?.disconnect()
        socket = nil
        
        #if os(macOS)
        if let proc = sshProcess {
            kill(proc.processIdentifier, SIGKILL)
        }
        sshProcess = nil
        #endif
        isUsingSshTunnel = false
        
        retryTimer?.invalidate()
        retryTimer = nil
        retryCountdown = 0
        // Don't reset retryAttempt here — let manual connect() do that
        
        connectionAttemptCount = 0
        DispatchQueue.main.async {
            self.isConnected = false
            self.isHandshakeComplete = false
            self.connectionStatus = "STATUS_DISCONNECTED"
            self.gatewaySessions = []
            self.serverDetected = false
            self.serverSetupNeeded = false
            self.isServerClawsyAware = false
            self.serverVersion = "unknown"
            self.rawLog += "\n[WSS] Disconnected (user-initiated)"
        }
    }
    
    // MARK: - WebSocketDelegate
    
    public func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL: Ensure log header is present at the very beginning of any activity
            if self.rawLog.isEmpty || !self.rawLog.contains("Clawsy") {
                let dateStr = ISO8601DateFormatter().string(from: Date())
                let header = "[LOG START] \(dateStr) | Clawsy \(SharedConfig.versionDisplay)\n----------------------------------------\n"
                self.rawLog = header + self.rawLog
            }
            
            switch event {
            case .connected(let headers):
                self.retryAttempt = 0
                self.retryCountdown = 0
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.rawLog += "\n[WSS] Connected (headers: \(headers.count))"
                self.connectionWatchdog?.invalidate()
                self.connectionWatchdog = nil
                self.isConnected = true
                self.connectionStatus = "STATUS_CONNECTED"
                self.connectionAttemptCount = 0
                // Note: connectionError is intentionally NOT cleared here.
                // It is only cleared after a successful handshake (hello-ok),
                // so the error banner stays visible during TCP-connected-but-handshake-pending states.
                // disconnectReason is also NOT cleared here — only after hello-ok (full handshake).
            case .disconnected(let reason, let code):
                self.rawLog += "\n[WSS] Disconnected: \(reason) (code: \(code))"
                self.isConnected = false
                if let classified = ConnectionError.classify(disconnectReason: reason, code: code) {
                    self.connectionError = classified
                }
                if !self.isHandshakeComplete && !self.isPairing {
                    if self.wasEverConnected {
                        // Reconnect attempt: handshake didn't complete (gateway still restarting).
                        // Treat as connectionLost to keep retrying.
                        self.disconnectReason = .connectionLost
                        self.rawLog += "\n[WSS] Handshake incomplete during reconnect — treating as connectionLost"
                        self.connectionAttemptCount = 0
                        self.scheduleRetry()
                    } else {
                        // First-time connection: handshake never completed (e.g. NOT_PAIRED).
                        // handleConnectionFailure will set .setupFailed and attempt SSH fallback once.
                        self.rawLog += "\n[WSS] Handshake incomplete — treating as setup failure"
                        self.handleConnectionFailure(err: nil)
                    }
                } else if self.isHandshakeComplete {
                    // Was fully connected — genuine connection loss → auto-reconnect.
                    self.disconnectReason = .connectionLost
                    self.rawLog += "\n[WSS] Connection lost after successful handshake — scheduling reconnect"
                    self.isHandshakeComplete = false
                    self.connectionAttemptCount = 0
                    self.retryAttempt = 0
                    self.scheduleRetry()
                } else {
                    self.connectionStatus = "STATUS_DISCONNECTED"
                }
            case .text(let string):
                self.rawLog += "\nIN: \(string)"
                self.handleMessage(string)
            case .error(let err):
                self.rawLog += "\n[WSS] Error: \(err?.localizedDescription ?? "nil")"
                self.isConnected = false
                
                // Classify: post-handshake errors are connection losses, pre-handshake are setup failures
                // Also treat pre-handshake errors during reconnect (wasEverConnected) as connectionLost
                if self.isHandshakeComplete || self.wasEverConnected {
                    self.disconnectReason = .connectionLost
                }
                // Pre-handshake first-time: disconnectReason will be set by handleConnectionFailure
                
                // Fast SSH fallback: if handshake never completed (e.g. firewall block, TCP refused)
                // and SSH fallback is available, skip retry backoff and go straight to SSH tunnel.
                // This prevents the "Verbindung wird wiederhergestellt..." loop on blocked firewalls.
                #if os(macOS)
                if !self.isHandshakeComplete && self.useSshFallback && !self.sshUser.isEmpty && !self.isUsingSshTunnel {
                    self.rawLog += "\n[WSS] Pre-handshake failure — fast-switching to SSH tunnel"
                    self.connectionWatchdog?.invalidate()
                    self.connectionWatchdog = nil
                    self.socket?.delegate = nil
                    self.socket?.disconnect()
                    self.socket = nil
                    self.startSshTunnel()
                    return
                }
                #endif
                self.handleConnectionFailure(err: err)
            case .viabilityChanged(let viable):
                self.rawLog += "\n[WSS] Viability: \(viable)"
            case .reconnectSuggested(let suggested):
                self.rawLog += "\n[WSS] ReconnectSuggested: \(suggested)"
            case .pong:
                break
            default: break
            }
        }
    }
    
    // One-Shot Send Logic
    private var oneShotPayload: (String, Any)?
    private var oneShotCompletion: ((Bool) -> Void)?

    /// One-shot send for Share Extension: connects, sends message via agent.deeplink, disconnects.
    public func sendOneShot(message: String, completion: @escaping (Bool) -> Void) {
        let send = { [weak self] in
            guard let self = self else { return }
            self.sendDeeplink(message: message, sessionKey: "clawsy-service")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion(true)
                self.disconnect()
            }
        }

        if isConnected && isHandshakeComplete {
            send()
            return
        }

        // Wait for handshake, then send
        var sent = false
        let obs = NotificationCenter.default.addObserver(forName: .init("ClawsyHandshakeComplete"), object: nil, queue: .main) { _ in
            guard !sent else { return }
            sent = true
            send()
        }
        onHandshakeComplete = { [weak self] in
            guard !sent else { return }
            sent = true
            NotificationCenter.default.removeObserver(obs)
            self?.onHandshakeComplete = nil
            send()
        }
        connect()

        // Timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
            guard !sent else { return }
            sent = true
            NotificationCenter.default.removeObserver(obs)
            completion(false)
            self.disconnect()
        }
    }

    @available(*, deprecated, message: "Use sendOneShot(message:) or sendDeeplink()")
    public func sendOneShot(kind: String, payload: Any, completion: @escaping (Bool) -> Void) {
        completion(false)
    }

    /// Called when agent info (model, agentName) is received via poll
    public var onAgentInfoUpdate: ((String?, String?) -> Void)?

    /// Called when task data changes (agentName, title, progress, statusText)
    public var onTaskUpdate: ((String, String, Double, String) -> Void)?

    // MARK: - State Polling (clawsy-service session via /tools/invoke)
    private var statePollerTimer: Timer?
    private let statePollerInterval: TimeInterval = 30
    private let stateTTLSeconds: TimeInterval = 2700  // ignore data older than 45 min (matches heartbeat rhythm)

    public func startStatePoller() {
        pollAgentState()
        statePollerTimer?.invalidate()
        statePollerTimer = Timer.scheduledTimer(withTimeInterval: statePollerInterval, repeats: true) { [weak self] _ in
            self?.pollAgentState()
        }
    }

    public func stopStatePoller() {
        statePollerTimer?.invalidate()
        statePollerTimer = nil
    }

    // MARK: - Gateway Sessions Polling (sessions.list every 10s)

    private func startSessionsPoller() {
        requestSessionsList()
        sessionsPollerTimer?.invalidate()
        sessionsPollerTimer = Timer.scheduledTimer(withTimeInterval: sessionsPollerInterval, repeats: true) { [weak self] _ in
            self?.requestSessionsList()
        }
    }

    private func stopSessionsPoller() {
        sessionsPollerTimer?.invalidate()
        sessionsPollerTimer = nil
        pendingSessionsListReqId = nil
    }

    private func requestSessionsList() {
        guard isHandshakeComplete, isConnected else { return }
        let reqId = UUID().uuidString
        pendingSessionsListReqId = reqId
        send(json: [
            "type": "req",
            "id": reqId,
            "method": "sessions.list",
            "params": ["activeMinutes": 60]
        ])
    }

    private func parseSessionsListResponse(_ result: Any) {
        guard let resultDict = result as? [String: Any],
              let sessions = resultDict["sessions"] as? [[String: Any]] else { return }

        let now = Date()
        let parsed: [GatewaySession] = sessions.compactMap { s in
            guard let key = s["key"] as? String else { return nil }

            let label = s["label"] as? String
            let kind = s["kind"] as? String ?? "direct"
            let model = s["model"] as? String

            // Derive status: "running" if updatedAt is within 5 min, "error" if aborted
            var status = "done"
            if let updatedAtMs = s["updatedAt"] as? Double {
                let updatedAt = Date(timeIntervalSince1970: updatedAtMs / 1000.0)
                if now.timeIntervalSince(updatedAt) <= sessionsActiveWindowSeconds {
                    status = "running"
                }
            }
            if s["abortedLastRun"] as? Bool == true { status = "error" }

            // startedAt not provided by gateway — use updatedAt as approximation
            var startedAt: Date? = nil
            if let updatedAtMs = s["updatedAt"] as? Double {
                startedAt = Date(timeIntervalSince1970: updatedAtMs / 1000.0)
            }

            return GatewaySession(
                id: key,
                label: label,
                kind: kind,
                status: status,
                model: model,
                startedAt: startedAt,
                task: nil
            )
        }

        DispatchQueue.main.async {
            self.gatewaySessions = parsed
        }
    }

    private func pollAgentState() {
        // Use same base URL logic as WebSocket connection
        let baseURL: String
        if isUsingSshTunnel {
            baseURL = "http://127.0.0.1:\(sshTunnelLocalPort)"
        } else {
            let host = serverHost.isEmpty ? "127.0.0.1" : serverHost
            let port = serverPort.isEmpty ? "18789" : serverPort
            let scheme = host.contains("://") ? "" : "http"
            baseURL = host.contains("://") ? host : "\(scheme)://\(host):\(port)"
        }
        guard let url = URL(string: "\(baseURL)/tools/invoke") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(serverToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10

        let body: [String: Any] = [
            "tool": "sessions_history",
            "args": ["sessionKey": "clawsy-service", "limit": 20]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data else { return }
            guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = outer["ok"] as? Bool, ok,
                  let result = outer["result"] as? [String: Any],
                  let contentArr = result["content"] as? [[String: Any]],
                  let text = contentArr.first?["text"] as? String,
                  let textData = text.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: textData) as? [String: Any],
                  let messages = payload["messages"] as? [[String: Any]] else { return }

            let now = Date()
            // Parse messages newest-first (already newest-first from limit), find latest of each kind
            var foundInfo = false
            var foundStatus = false
            for msg in messages {
                guard !foundInfo || !foundStatus else { break }
                guard let role = msg["role"] as? String, role == "user",
                      let contentBlocks = msg["content"] as? [[String: Any]],
                      let textBlock = contentBlocks.first(where: { $0["type"] as? String == "text" }),
                      let rawText = textBlock["text"] as? String,
                      let msgData = rawText.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any],
                      let kind = json["kind"] as? String,
                      let msgPayload = json["payload"] as? [String: Any] else { continue }

                // TTL check
                if let updatedAt = msgPayload["updatedAt"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: updatedAt) ?? ISO8601DateFormatter().date(from: updatedAt) {
                        if now.timeIntervalSince(date) > self.stateTTLSeconds { continue }
                    }
                }

                if kind == "agent.info", !foundInfo {
                    foundInfo = true
                    let model = msgPayload["model"] as? String
                    let name = msgPayload["agentName"] as? String
                    DispatchQueue.main.async {
                        self.onAgentInfoUpdate?(model, name)
                        // agent.info confirms the OpenClaw agent is active → gateway is fully aware
                        self.isServerClawsyAware = true
                        self.serverVersion = model ?? "OpenClaw"
                    }
                }
                if kind == "agent.status", !foundStatus {
                    foundStatus = true
                    let agent = msgPayload["agentName"] as? String ?? "Unknown"
                    let title = msgPayload["title"] as? String ?? ""
                    let progress = msgPayload["progress"] as? Double ?? 0.0
                    let status = msgPayload["statusText"] as? String ?? ""
                    DispatchQueue.main.async { self.onTaskUpdate?(agent, title, progress, status) }
                }
            }
        }.resume()
    }

    /// Probes whether the clawsy-bridge gateway plugin is active on the remote host.
    /// Called once after a successful auth handshake (Case B detection).
    private func detectClawsyServer() {
        let baseURL: String
        if isUsingSshTunnel {
            baseURL = "http://127.0.0.1:\(sshTunnelLocalPort)"
        } else {
            let host = serverHost.isEmpty ? "127.0.0.1" : serverHost
            let port = serverPort.isEmpty ? "18789" : serverPort
            baseURL = "http://\(host):\(port)"
        }
        guard let url = URL(string: "\(baseURL)/tools/invoke") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(serverToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body: [String: Any] = [
            "tool": "exec",
            "args": ["command": "openclaw plugins info clawsy-bridge 2>/dev/null | grep -q 'enabled: true' && echo ACTIVE || echo MISSING"]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let output = result["output"] as? String else { return }
            let active = output.trimmingCharacters(in: .whitespacesAndNewlines) == "ACTIVE"
            DispatchQueue.main.async {
                self.serverSetupNeeded = !active
            }
        }.resume()
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // agent.info and agent.status are delivered via pollAgentState() (sessions_history over HTTP)
        // No WS handlers needed for these — polling is the single source of truth

        let rawId = json["id"]
        let isValidId: Bool
        if let s = rawId as? String { isValidId = !s.isEmpty } else { isValidId = rawId is Int }
        
        let method = json["method"] as? String
        let event = json["event"] as? String
        let command = json["command"] as? String
        let commandName = method ?? event ?? command
        
        if let name = commandName, (name == "tick" || name == "health") { return }

        if event == "connect.challenge" {
            if let payload = json["payload"] as? [String: Any], let nonce = payload["nonce"] as? String {
                performHandshake(nonce: nonce)
            }
            return
        }
        
        if event == "node.pair.requested" {
            self.isPairing = true
            self.connectionWatchdog?.invalidate()
            self.connectionWatchdog = nil
            self.connectionStatus = "STATUS_PAIRING_PENDING"
            self.rawLog += "\n[PAIR] Pairing pending – awaiting admin approval"
            return
        }
        
        if event == "node.pair.resolved" {
            self.isPairing = false
            self.pairingRequestId = ""
            self.pairingTimeoutTimer?.invalidate()
            self.pairingTimeoutTimer = nil
            if let payload = json["payload"] as? [String: Any] {
                let approved = payload["approved"] as? Bool ?? false
                if approved, let dt = payload["deviceToken"] as? String {
                    self.deviceToken = dt
                    self.rawLog += "\n[PAIR] Pairing approved – reconnecting with deviceToken"
                    self.connect()
                } else {
                    self.connectionStatus = "STATUS_PAIRING_REJECTED"
                    self.rawLog += "\n[PAIR] Pairing rejected"
                }
            }
            return
        }
        
        if event == "node.invoke.request", let payload = json["payload"] as? [String: Any], let invocationId = payload["id"] as? String {
            let command = payload["command"] as? String ?? ""
            var innerParams: [String: Any] = [:]
            if let paramsJSON = payload["paramsJSON"] as? String, let data = paramsJSON.data(using: .utf8) {
                innerParams = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            }
            handleCommand(id: "inv:\(invocationId)", command: command, params: innerParams)
            return
        }
        
        let type = json["type"] as? String
        if type == "res" || type == "response" || type == "error" {
            if let rid = rawId as? String {
                // sessions.list response
                if let pendingId = pendingSessionsListReqId, rid == pendingId {
                    pendingSessionsListReqId = nil
                    if let result = json["result"] {
                        parseSessionsListResponse(result)
                    }
                    return
                }

                if rid == "1" {
                let payload = json["payload"] as? [String: Any]
                if payload?["type"] as? String == "hello-ok" || json["result"] != nil {
                     self.isHandshakeComplete = true
                     self.wasEverConnected = true  // Mark: handshake succeeded at least once
                     self.connectionStatus = isUsingSshTunnel ? "STATUS_ONLINE_PAIRED_SSH" : "STATUS_ONLINE_PAIRED"
                     self.connectionError = nil
                     self.disconnectReason = nil  // Session is live — reset for future disconnect classification
                     self.onHandshakeComplete?()
                     
                     // Store deviceToken from hello-ok if present.
                     // NOTE: deviceToken is for node pairing identity only — NOT for gateway auth.
                     // Gateway auth always uses serverToken (gateway.auth.token). See performHandshake().
                     if let result = json["result"] as? [String: Any],
                        let auth = result["auth"] as? [String: Any],
                        let dt = auth["deviceToken"] as? String {
                         self.deviceToken = dt
                     } else if let p = payload,
                               let auth = p["auth"] as? [String: Any],
                               let dt = auth["deviceToken"] as? String {
                         self.deviceToken = dt
                     }
                     
                     // Connected + paired = gateway IS the server.
                     self.serverDetected = true
                     self.serverSetupNeeded = false

                     // Probe whether clawsy-bridge plugin is active (Case B detection)
                     self.detectClawsyServer()

                     // Start gateway sessions poller
                     self.startSessionsPoller()
                     
                     // Check for pending one-shot
                     if let (kind, payload) = self.oneShotPayload {
                         self.sendEvent(kind: kind, payload: payload)
                         self.oneShotCompletion?(true)
                         self.oneShotPayload = nil
                         // Small delay before disconnect to ensure delivery
                         DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                             self.disconnect()
                         }
                     }
                } else if let errorObj = json["error"] as? [String: Any],
                          let errorCode = errorObj["code"] as? String, errorCode == "NOT_PAIRED" {
                     let details = errorObj["details"] as? [String: Any]
                     let requestId = details?["requestId"] as? String ?? ""
                     
                     #if os(macOS)
                     // Strategy: If we're connected via direct WSS (not SSH tunnel) and SSH
                     // fallback is available, reconnect through SSH. Localhost connections get
                     // auto-approved pairing on the server side — no manual approval needed.
                     // This is THE key insight from the 2026-03-05 connection incident.
                     if !self.isUsingSshTunnel && self.useSshFallback && !self.sshUser.isEmpty {
                         self.rawLog += "\n[PAIR] NOT_PAIRED via WSS – switching to SSH tunnel for auto-pairing"
                         // Clean up WS without setting userInitiated — this is an internal fallback, not user action.
                         self.socket?.delegate = nil
                         self.socket?.disconnect()
                         self.socket = nil
                         self.isPairing = false
                         self.disconnectReason = nil
                         self.startSshTunnel()
                         return
                     }
                     #endif
                     
                     // No SSH available — show pairing instructions to user
                     self.isPairing = true
                     self.pairingRequestId = requestId
                     self.connectionStatus = requestId.isEmpty ? "STATUS_PAIRING" : "STATUS_AWAITING_PAIR_APPROVE"
                     
                     self.connectionWatchdog?.invalidate()
                     self.connectionWatchdog = nil
                     
                     self.pairingTimeoutTimer?.invalidate()
                     self.pairingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
                         guard let self = self else { return }
                         DispatchQueue.main.async {
                             self.rawLog += "\n[PAIR] Pairing timeout (5 min) – disconnecting"
                             self.connectionStatus = "STATUS_PAIRING_TIMEOUT"
                             self.disconnect()
                         }
                     }
                     
                     self.rawLog += "\n[PAIR] NOT_PAIRED – sending node.pair.request (requestId: \(requestId))"
                     let pairReq: [String: Any] = [
                         "type": "req", "id": "2", "method": "node.pair.request",
                         "params": ["requestId": requestId, "silent": true]
                     ]
                     self.send(json: pairReq)
                } else if let errorObj = json["error"] as? [String: Any],
                          let errorCode = errorObj["code"] as? String,
                          errorCode == "AUTH_TOKEN_MISMATCH" {
                     // Genuine auth failure — clear stale token and stop.
                     self.rawLog += "\n[AUTH] \(errorCode) – clearing deviceToken, no auto-reconnect"
                     self.deviceToken = nil
                     self.wasEverConnected = false
                     self.disconnectReason = .setupFailed(errorCode)
                     self.isHandshakeComplete = false
                     self.connectionStatus = "STATUS_HANDSHAKE_FAILED"
                     // If we got here via SSH tunnel, the gateway is reachable but the
                     // Clawsy server skill is likely not installed — show a specific hint.
                     if self.isUsingSshTunnel {
                         self.connectionError = .skillMissingAfterSsh
                     } else {
                         self.connectionError = .invalidToken
                     }
                } else if let errorObj = json["error"] as? [String: Any],
                          let errorCode = errorObj["code"] as? String,
                          errorCode == "INVALID_REQUEST" {
                     // INVALID_REQUEST may be a schema mismatch (e.g. unknown property),
                     // not necessarily an auth problem. If we were connected before, retry.
                     let errorMsg = (errorObj["message"] as? String) ?? errorCode
                     if self.wasEverConnected {
                         self.rawLog += "\n[AUTH] \(errorCode) during reconnect – retrying (\(errorMsg))"
                         self.disconnectReason = .connectionLost
                         self.connectionAttemptCount = 0
                         self.scheduleRetry()
                     } else {
                         self.rawLog += "\n[AUTH] \(errorCode) – setup failed (\(errorMsg))"
                         self.disconnectReason = .setupFailed(errorCode)
                         self.isHandshakeComplete = false
                         self.connectionStatus = "STATUS_HANDSHAKE_FAILED"
                         self.connectionError = .invalidToken
                     }
                } else if json["error"] != nil {
                     self.isHandshakeComplete = false
                     self.connectionStatus = "STATUS_HANDSHAKE_FAILED"
                     self.connectionError = .invalidToken
                }
                }
            }
            return
        }
        
        if let name = commandName {
            let params = json["params"] as? [String: Any] ?? json["payload"] as? [String: Any] ?? [:]
            if isValidId, let id = rawId {
                var effectiveCommand = name
                var effectiveParams = params
                var effectiveId = id
                if name == "node.invoke" {
                    if let cmd = params["command"] as? String { effectiveCommand = cmd }
                    if let nested = params["params"] as? [String: Any] { effectiveParams = nested }
                    effectiveId = "wrap:\(id)"
                }
                handleCommand(id: effectiveId, command: effectiveCommand, params: effectiveParams)
            }
            return
        }
    }
    
    private var deviceId: String {
        guard let pubKeyData = publicKey?.rawRepresentation else { return "node" }
        return SHA256.hash(data: pubKeyData).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Connection Identity Constants
    // These are the single source of truth for both signature payload AND connect params.
    // NEVER define these values separately — that's how signature mismatches happen.
    // See: 2026-03-05 scopes mismatch incident (v0.7.5 fix).
    private static let connectRole = "node"
    private static let connectClientMode = "node"
    private static let connectScopes = ["operator.read"]
    
    #if os(macOS)
    private static let connectPlatform = "macos"
    #elseif os(iOS)
    private static let connectPlatform = "ios"
    #elseif os(tvOS)
    private static let connectPlatform = "tvos"
    #else
    private static let connectPlatform = "unknown"
    #endif

    private var connectClientId: String { "openclaw-\(Self.connectPlatform)" }

    private func performHandshake(nonce: String) {
        guard let signingKey = signingKey, let publicKey = publicKey else { return }
        let tsMs = Int64(Date().timeIntervalSince1970 * 1000)
        let deviceId = self.deviceId
        
        // deviceToken is for node pairing, NOT gateway auth.
        // Using deviceToken here caused AUTH_TOKEN_MISMATCH on reconnect
        // for non-Tailscale connections (SSH tunnel, direct WSS).
        let authToken = serverToken
        let scopesString = Self.connectScopes.joined(separator: ",")
        
        // Protocol V2: version|deviceId|clientId|clientMode|role|scopes|ts|token|nonce
        // All values come from the shared constants above — same source as the connect params.
        let components = ["v2", deviceId, connectClientId, Self.connectClientMode, Self.connectRole, scopesString, String(tsMs), authToken, nonce]
        let payloadString = components.joined(separator: "|")
        guard let payloadData = payloadString.data(using: .utf8) else { return }
        guard let signature = try? signingKey.signature(for: payloadData) else { return }
        let pubKeyB64 = base64UrlEncode(publicKey.rawRepresentation)
        let sigB64 = base64UrlEncode(signature)
        
        // NOTE: setupState was removed from connect params — the current gateway rejects
        // unknown properties with INVALID_REQUEST, breaking the connection entirely.
        // Re-add setupState once the gateway schema is updated to accept it.

        let connectReq: [String: Any] = [
            "type": "req", "id": "1", "method": "connect",
            "params": [
                "minProtocol": 3, "maxProtocol": 3,
                "client": ["id": connectClientId, "version": SharedConfig.versionDisplay, "platform": Self.connectPlatform, "mode": Self.connectClientMode],
                "role": Self.connectRole, "caps": ["clipboard", "screen", "camera", "file", "location"],
                "scopes": Self.connectScopes,
                "commands": ["clipboard.read", "clipboard.write", "screen.capture", "camera.list", "camera.snap", "file.list", "file.get", "file.set", "file.get.chunk", "file.set.chunk", "file.delete", "file.rename", "file.move", "file.copy", "file.mkdir", "file.rmdir", "file.stat", "file.exists", "file.batch", "location.get", "location.start", "location.stop", "location.add_smart"],
                "permissions": ["clipboard.read": true, "clipboard.write": true],
                "auth": ["token": authToken],
                "device": [
                    "id": deviceId, "publicKey": pubKeyB64, "signature": sigB64, "signedAt": tsMs, "nonce": nonce
                ]
            ]
        ]
        send(json: connectReq)
    }
    
    private func handleCommand(id: Any, command: String, params: [String: Any]) {
        let baseDir = sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        if command.hasPrefix("file.") && !ClawsyFileManager.folderExists(at: baseDir) {
            sendError(id: id, code: -32000, message: "Folder not configured")
            return
        }
        
        switch command {
        case "screen.capture":
            let interactive = params["interactive"] as? Bool ?? false
            onScreenshotRequested?(interactive, id)
        case "camera.list":
            let cameras = CameraManager.listCameras()
            sendResponse(id: id, result: ["cameras": cameras])
        case "camera.snap":
            let deviceId = params["deviceId"] as? String
            let preview = params["preview"] as? Bool ?? false
            CameraManager.takePhoto(deviceId: deviceId) { b64 in
                guard let b64 = b64, let data = Data(base64Encoded: b64), let image = ClawsyImage(data: data) else {
                    self.sendError(id: id, code: -32000, message: "Camera capture failed")
                    return
                }
                if preview {
                    DispatchQueue.main.async { self.onCameraPreviewRequested?(image, { self.sendResponse(id: id, result: ["content": b64]) }, { self.sendError(id: id, code: -1, message: "User rejected camera image") }) }
                } else { self.sendResponse(id: id, result: ["content": b64]) }
            }
        case "clipboard.read": onClipboardReadRequested?(id)
        case "clipboard.write":
            if let content = params["text"] as? String { onClipboardWriteRequested?(content, id) } else { sendError(id: id, code: -32602, message: "Missing 'text' parameter") }
            
        case "location.get":
            if let loc = locationManager.lastLocation {
                sendResponse(id: id, result: loc)
            } else {
                sendError(id: id, code: -32000, message: "Location not available")
            }
            
        case "location.start":
            locationManager.startUpdating()
            sendResponse(id: id, result: ["status": "started"])
            
        case "location.stop":
            locationManager.stopUpdating()
            sendResponse(id: id, result: ["status": "stopped"])
            
        case "location.add_smart":
            guard let name = params["name"] as? String,
                  let lat = params["lat"] as? Double,
                  let lon = params["lon"] as? Double else {
                sendError(id: id, code: -32602, message: "Missing params (name, lat, lon)")
                return
            }
            locationManager.addSmartLocation(name: name, lat: lat, lon: lon)
            sendResponse(id: id, result: ["status": "added", "name": name])
            
        case "file.list":
            self.sendAck(id: id)
            let subPath = params["subPath"] as? String ?? params["path"] as? String ?? ""
            let recursive = params["recursive"] as? Bool ?? false
            // Validate subPath stays within sandbox
            if !subPath.isEmpty {
                guard ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: subPath) != nil else {
                    sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
                }
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let files = ClawsyFileManager.listFiles(at: baseDir, subPath: subPath, recursive: recursive)
                let result = files.map { ["name": $0.name, "isDirectory": $0.isDirectory, "size": $0.size, "modified": $0.modified.timeIntervalSince1970] }
                self.sendResponse(id: id, result: ["files": result, "path": self.sharedFolderPath])
            }
        case "file.get":
            guard let name = params["name"] as? String else { sendError(id: id, code: -32602, message: "Missing 'name' parameter"); return }
            // System files are answered automatically without user interaction or notifications
            if name == ".clawsy_version" {
                self.sendAck(id: id)
                let versionData = SharedConfig.versionDisplay.data(using: .utf8) ?? Data()
                self.sendResponse(id: id, result: ["content": versionData.base64EncodedString(), "name": name])
                return
            }
            guard let fullPath = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: name) else {
                sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
            }
            self.sendAck(id: id)
            let executeGet = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .clawsy, comment: ""), body: String(format: NSLocalizedString("NOTIFICATION_BODY_DOWNLOADING", bundle: .clawsy, comment: ""), name), isAuto: ({ if let exp = self.filePermissionExpiry { return exp > Date() } else { return false } }()))
                DispatchQueue.global(qos: .userInitiated).async {
                    switch ClawsyFileManager.readFile(at: fullPath) {
                    case .success(let b64):
                        self.sendResponse(id: id, result: ["content": b64, "name": name])
                    case .failure(let error):
                        self.sendError(id: id, code: -32000, message: "Failed to read file: \(error.description)")
                    }
                }
            }
            if let expiry = filePermissionExpiry, expiry > Date() { executeGet() } else { onFileSyncRequested?(name, "Download", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeGet() }, { self.sendError(id: id, code: -1, message: "User denied file access") }) }
        case "file.set":
            guard let name = params["name"] as? String, let content = params["content"] as? String else { sendError(id: id, code: -32602, message: "Missing 'name' or 'content' parameter"); return }
            guard let fullPath = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: name) else {
                sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
            }
            self.sendAck(id: id)
            let executeSet = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .clawsy, comment: ""), body: String(format: NSLocalizedString("NOTIFICATION_BODY_UPLOADING", bundle: .clawsy, comment: ""), name), isAuto: ({ if let exp = self.filePermissionExpiry { return exp > Date() } else { return false } }()))
                DispatchQueue.global(qos: .userInitiated).async {
                    switch ClawsyFileManager.writeFile(at: fullPath, base64Content: content) {
                    case .success:
                        self.sendResponse(id: id, result: ["status": "ok", "name": name])
                    case .failure(let error):
                        self.sendError(id: id, code: -32000, message: "Failed to write file: \(error.description)")
                    }
                }
            }
            // System-internal files are always allowed silently — no permission dialog
            let silentWriteAllowlist: Set<String> = [".agent_status.json", ".agent_info.json", ".clawsy_version"]
            if silentWriteAllowlist.contains(name) {
                executeSet()
            } else if let expiry = filePermissionExpiry, expiry > Date() {
                executeSet()
            } else {
                onFileSyncRequested?(name, "Upload", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeSet() }, { self.sendError(id: id, code: -1, message: "User denied file write") })
            }
        case "file.set.chunk":
            guard let name = params["name"] as? String,
                  let chunkIndex = params["chunkIndex"] as? Int,
                  let totalChunks = params["totalChunks"] as? Int,
                  let content = params["content"] as? String else {
                sendError(id: id, code: -32602, message: "Missing parameters"); return
            }
            guard let fullPathChunkSet = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: name) else {
                sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
            }
            self.sendAck(id: id)
            let executeChunk = {
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let chunkData = Data(base64Encoded: content) else {
                        self.sendError(id: id, code: -32000, message: "Invalid base64 chunk"); return
                    }
                    guard let tempPath = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: ".\(name).clawsy_chunk_\(chunkIndex)") else {
                        self.sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
                    }
                    do {
                        try chunkData.write(to: URL(fileURLWithPath: tempPath))
                    } catch {
                        self.sendError(id: id, code: -32000, message: "Failed to write chunk: \(error)"); return
                    }
                    if chunkIndex == totalChunks - 1 {
                        var assembled = Data()
                        for i in 0..<totalChunks {
                            guard let tp = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: ".\(name).clawsy_chunk_\(i)") else {
                                self.sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
                            }
                            if let cd = try? Data(contentsOf: URL(fileURLWithPath: tp)) {
                                assembled.append(cd)
                                try? FileManager.default.removeItem(atPath: tp)
                            } else {
                                self.sendError(id: id, code: -32000, message: "Missing chunk \(i)"); return
                            }
                        }
                        let assembledB64 = assembled.base64EncodedString()
                        switch ClawsyFileManager.writeFile(at: fullPathChunkSet, base64Content: assembledB64) {
                        case .success:
                            self.sendResponse(id: id, result: ["status": "ok", "name": name, "assembled": true])
                        case .failure:
                            self.sendError(id: id, code: -32000, message: "Failed to assemble file")
                        }
                    } else {
                        self.sendResponse(id: id, result: ["status": "chunk_received", "chunkIndex": chunkIndex])
                    }
                }
            }
            let silentChunkAllowlist: Set<String> = [".agent_status.json", ".agent_info.json", ".clawsy_version"]
            if silentChunkAllowlist.contains(name) || chunkIndex > 0 {
                executeChunk()
            } else if let expiry = filePermissionExpiry, expiry > Date() {
                executeChunk()
            } else {
                onFileSyncRequested?(name, "Upload (chunked)", { duration in if let d = duration { self.filePermissionExpiry = Date().addingTimeInterval(d) }; executeChunk() }, { self.sendError(id: id, code: -1, message: "User denied") })
            }
        case "file.get.chunk":
            guard let name = params["name"] as? String,
                  let chunkIndex = params["chunkIndex"] as? Int else {
                sendError(id: id, code: -32602, message: "Missing parameters"); return
            }
            let chunkSizeBytes = (params["chunkSizeBytes"] as? Int) ?? 262144
            guard let fullPathChunkGet = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: name) else {
                sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
            }
            self.sendAck(id: id)
            let executeGetChunk = {
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let data = FileManager.default.contents(atPath: fullPathChunkGet) else {
                        self.sendError(id: id, code: -32000, message: "Failed to read file"); return
                    }
                    let totalBytes = data.count
                    let totalChunks = max(1, Int(ceil(Double(totalBytes) / Double(chunkSizeBytes))))
                    guard chunkIndex < totalChunks else {
                        self.sendError(id: id, code: -32000, message: "Chunk index out of range"); return
                    }
                    let start = chunkIndex * chunkSizeBytes
                    let end = min(start + chunkSizeBytes, totalBytes)
                    let chunkData = data.subdata(in: start..<end)
                    let chunkB64 = chunkData.base64EncodedString()
                    self.sendResponse(id: id, result: [
                        "content": chunkB64,
                        "chunkIndex": chunkIndex,
                        "totalChunks": totalChunks,
                        "totalBytes": totalBytes,
                        "name": name
                    ])
                }
            }
            if chunkIndex > 0 {
                executeGetChunk()
            } else if let expiry = filePermissionExpiry, expiry > Date() {
                executeGetChunk()
            } else {
                onFileSyncRequested?(name, "Download (chunked)", { duration in if let d = duration { self.filePermissionExpiry = Date().addingTimeInterval(d) }; executeGetChunk() }, { self.sendError(id: id, code: -1, message: "User denied") })
            }
        case "file.delete", "file.rmdir":
            guard let name = params["name"] as? String else { sendError(id: id, code: -32602, message: "Missing 'name' parameter"); return }
            self.sendAck(id: id)
            let executeDelete = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .clawsy, comment: ""), body: "Deleted: \(name)", isAuto: ({ if let exp = self.filePermissionExpiry { return exp > Date() } else { return false } }()))
                DispatchQueue.global(qos: .userInitiated).async {
                    // Glob pattern support
                    if ClawsyFileManager.isGlobPattern(name) {
                        guard let matches = ClawsyFileManager.resolveGlob(baseDir: baseDir, pattern: name) else {
                            self.sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
                        }
                        var successCount = 0
                        var errors: [[String: Any]] = []
                        for match in matches {
                            if let fullPath = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: match) {
                                switch ClawsyFileManager.deleteFile(at: fullPath) {
                                case .success:
                                    successCount += 1
                                case .failure(let error):
                                    errors.append(["file": match, "error": "Delete failed: \(error.description)"])
                                }
                            } else { errors.append(["file": match, "error": "Path traversal"]) }
                        }
                        self.sendResponse(id: id, result: ["status": "ok", "matched": matches.count, "success": successCount, "errors": errors])
                    } else {
                        guard let fullPath = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: name) else {
                            self.sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
                        }
                        switch ClawsyFileManager.deleteFile(at: fullPath) {
                        case .success:
                            self.sendResponse(id: id, result: ["status": "ok", "name": name])
                        case .failure(let error):
                            self.sendError(id: id, code: -32000, message: "Failed to delete file: \(error.description)")
                        }
                    }
                }
            }
            if let expiry = filePermissionExpiry, expiry > Date() { executeDelete() } else { onFileSyncRequested?(name, "Delete", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeDelete() }, { self.sendError(id: id, code: -1, message: "User denied file delete") }) }
        case "file.mkdir":
            guard let name = params["name"] as? String else { sendError(id: id, code: -32602, message: "Missing 'name' parameter"); return }
            guard let fullPathMkdir = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: name) else {
                sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
            }
            self.sendAck(id: id)
            DispatchQueue.global(qos: .userInitiated).async {
                switch ClawsyFileManager.createDirectory(at: fullPathMkdir) {
                case .success:
                    self.sendResponse(id: id, result: ["success": true, "name": name])
                case .failure(let error):
                    self.sendResponse(id: id, result: ["success": false, "name": name, "error": error.description])
                }
            }
        case "file.move":
            guard let source = params["source"] as? String, let destination = params["destination"] as? String else {
                sendError(id: id, code: -32602, message: "Missing 'source' or 'destination' parameter"); return
            }
            self.sendAck(id: id)
            let executeMove = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .clawsy, comment: ""), body: "Moved: \(source) → \(destination)", isAuto: ({ if let exp = self.filePermissionExpiry { return exp > Date() } else { return false } }()))
                DispatchQueue.global(qos: .userInitiated).async {
                    // Glob pattern support
                    if ClawsyFileManager.isGlobPattern(source) {
                        guard let matches = ClawsyFileManager.resolveGlob(baseDir: baseDir, pattern: source) else {
                            self.sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
                        }
                        var successCount = 0
                        var errors: [[String: Any]] = []
                        for match in matches {
                            let destPath = (destination as NSString).appendingPathComponent((match as NSString).lastPathComponent)
                            let result = ClawsyFileManager.moveFile(baseDir: baseDir, source: match, destination: destPath)
                            switch result {
                            case .success: successCount += 1
                            case .failure(let err): errors.append(["file": match, "error": err.description])
                            }
                        }
                        self.sendResponse(id: id, result: ["status": "ok", "matched": matches.count, "success": successCount, "errors": errors])
                    } else {
                        let result = ClawsyFileManager.moveFile(baseDir: baseDir, source: source, destination: destination)
                        switch result {
                        case .success:
                            self.sendResponse(id: id, result: ["status": "ok", "source": source, "destination": destination])
                        case .failure(let error):
                            let code: Int
                            switch error {
                            case .sourceNotFound: code = -32001
                            case .destinationExists: code = -32002
                            case .pathTraversal: code = -32003
                            case .moveFailed: code = -32000
                            }
                            self.sendError(id: id, code: code, message: error.description)
                        }
                    }
                }
            }
            if let expiry = filePermissionExpiry, expiry > Date() { executeMove() } else { onFileSyncRequested?(source, "Move to \(destination)", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeMove() }, { self.sendError(id: id, code: -1, message: "User denied file move") }) }
        case "file.copy":
            guard let source = params["source"] as? String, let destination = params["destination"] as? String else {
                sendError(id: id, code: -32602, message: "Missing 'source' or 'destination' parameter"); return
            }
            self.sendAck(id: id)
            let executeCopy = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .clawsy, comment: ""), body: "Copied: \(source) → \(destination)", isAuto: ({ if let exp = self.filePermissionExpiry { return exp > Date() } else { return false } }()))
                DispatchQueue.global(qos: .userInitiated).async {
                    if ClawsyFileManager.isGlobPattern(source) {
                        guard let matches = ClawsyFileManager.resolveGlob(baseDir: baseDir, pattern: source) else {
                            self.sendError(id: id, code: -32003, message: "Path must stay within the shared folder"); return
                        }
                        var successCount = 0
                        var errors: [[String: Any]] = []
                        for match in matches {
                            let destPath = (destination as NSString).appendingPathComponent((match as NSString).lastPathComponent)
                            let result = ClawsyFileManager.copyFile(baseDir: baseDir, source: match, destination: destPath)
                            switch result {
                            case .success: successCount += 1
                            case .failure(let err): errors.append(["file": match, "error": err.description])
                            }
                        }
                        self.sendResponse(id: id, result: ["status": "ok", "matched": matches.count, "success": successCount, "errors": errors])
                    } else {
                        let result = ClawsyFileManager.copyFile(baseDir: baseDir, source: source, destination: destination)
                        switch result {
                        case .success:
                            self.sendResponse(id: id, result: ["status": "ok", "source": source, "destination": destination])
                        case .failure(let error):
                            let code: Int
                            switch error {
                            case .sourceNotFound: code = -32001
                            case .destinationExists: code = -32002
                            case .pathTraversal: code = -32003
                            case .moveFailed: code = -32000
                            }
                            self.sendError(id: id, code: code, message: error.description)
                        }
                    }
                }
            }
            if let expiry = filePermissionExpiry, expiry > Date() { executeCopy() } else { onFileSyncRequested?(source, "Copy to \(destination)", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeCopy() }, { self.sendError(id: id, code: -1, message: "User denied file copy") }) }
        case "file.rename":
            let path = params["path"] as? String ?? params["name"] as? String
            guard let path = path, let newName = params["newName"] as? String else { sendError(id: id, code: -32602, message: "Missing 'path' or 'newName' parameter"); return }
            self.sendAck(id: id)
            let executeRename = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .clawsy, comment: ""), body: "Renamed: \(path) → \(newName)", isAuto: ({ if let exp = self.filePermissionExpiry { return exp > Date() } else { return false } }()))
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = ClawsyFileManager.renameFile(baseDir: baseDir, path: path, newName: newName)
                    switch result {
                    case .success:
                        self.sendResponse(id: id, result: ["status": "ok", "path": path, "newName": newName])
                    case .failure(let error):
                        let code: Int
                        switch error {
                        case .sourceNotFound: code = -32001
                        case .destinationExists: code = -32002
                        case .pathTraversal: code = -32003
                        case .moveFailed: code = -32000
                        }
                        self.sendError(id: id, code: code, message: error.description)
                    }
                }
            }
            if let expiry = filePermissionExpiry, expiry > Date() { executeRename() } else { onFileSyncRequested?(path, "Rename to \(newName)", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeRename() }, { self.sendError(id: id, code: -1, message: "User denied file rename") }) }
        case "file.stat":
            let path = params["path"] as? String ?? ""
            guard !path.isEmpty else { sendError(id: id, code: -32602, message: "Missing 'path' parameter"); return }
            self.sendAck(id: id)
            DispatchQueue.global(qos: .userInitiated).async {
                let stat = ClawsyFileManager.statFile(baseDir: baseDir, relativePath: path)
                if let data = try? JSONEncoder().encode(stat),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.sendResponse(id: id, result: dict)
                } else {
                    self.sendError(id: id, code: -32000, message: "Failed to serialize file stat")
                }
            }
        case "file.exists":
            let path = params["path"] as? String ?? ""
            guard !path.isEmpty else { sendError(id: id, code: -32602, message: "Missing 'path' parameter"); return }
            self.sendAck(id: id)
            DispatchQueue.global(qos: .userInitiated).async {
                let result = ClawsyFileManager.existsFile(baseDir: baseDir, relativePath: path)
                if let data = try? JSONEncoder().encode(result),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.sendResponse(id: id, result: dict)
                } else {
                    self.sendError(id: id, code: -32000, message: "Failed to serialize existence check")
                }
            }
        case "file.batch":
            guard let ops = params["ops"] as? [[String: Any]] else {
                sendError(id: id, code: -32602, message: "Missing 'ops' parameter"); return
            }
            self.sendAck(id: id)
            let executeBatch = {
                DispatchQueue.global(qos: .userInitiated).async {
                    var results: [[String: Any]] = []
                    for (index, op) in ops.enumerated() {
                        guard let opType = op["op"] as? String else {
                            results.append(["index": index, "op": "unknown", "success": false, "error": "Missing 'op' field"])
                            continue
                        }
                        switch opType {
                        case "move":
                            guard let src = op["src"] as? String, let dst = op["dst"] as? String else {
                                results.append(["index": index, "op": opType, "success": false, "error": "Missing src/dst"]); continue
                            }
                            if ClawsyFileManager.isGlobPattern(src) {
                                guard let matches = ClawsyFileManager.resolveGlob(baseDir: baseDir, pattern: src) else {
                                    results.append(["index": index, "op": opType, "success": false, "error": "Path traversal"]); continue
                                }
                                var successCount = 0; var errors: [[String: Any]] = []
                                for match in matches {
                                    let destPath = (dst as NSString).appendingPathComponent((match as NSString).lastPathComponent)
                                    switch ClawsyFileManager.moveFile(baseDir: baseDir, source: match, destination: destPath) {
                                    case .success: successCount += 1
                                    case .failure(let e): errors.append(["file": match, "error": e.description])
                                    }
                                }
                                results.append(["index": index, "op": opType, "success": errors.isEmpty, "matched": matches.count, "successCount": successCount, "errors": errors])
                            } else {
                                switch ClawsyFileManager.moveFile(baseDir: baseDir, source: src, destination: dst) {
                                case .success: results.append(["index": index, "op": opType, "success": true])
                                case .failure(let e): results.append(["index": index, "op": opType, "success": false, "error": e.description])
                                }
                            }
                        case "copy":
                            guard let src = op["src"] as? String, let dst = op["dst"] as? String else {
                                results.append(["index": index, "op": opType, "success": false, "error": "Missing src/dst"]); continue
                            }
                            if ClawsyFileManager.isGlobPattern(src) {
                                guard let matches = ClawsyFileManager.resolveGlob(baseDir: baseDir, pattern: src) else {
                                    results.append(["index": index, "op": opType, "success": false, "error": "Path traversal"]); continue
                                }
                                var successCount = 0; var errors: [[String: Any]] = []
                                for match in matches {
                                    let destPath = (dst as NSString).appendingPathComponent((match as NSString).lastPathComponent)
                                    switch ClawsyFileManager.copyFile(baseDir: baseDir, source: match, destination: destPath) {
                                    case .success: successCount += 1
                                    case .failure(let e): errors.append(["file": match, "error": e.description])
                                    }
                                }
                                results.append(["index": index, "op": opType, "success": errors.isEmpty, "matched": matches.count, "successCount": successCount, "errors": errors])
                            } else {
                                switch ClawsyFileManager.copyFile(baseDir: baseDir, source: src, destination: dst) {
                                case .success: results.append(["index": index, "op": opType, "success": true])
                                case .failure(let e): results.append(["index": index, "op": opType, "success": false, "error": e.description])
                                }
                            }
                        case "delete":
                            guard let src = op["src"] as? String else {
                                results.append(["index": index, "op": opType, "success": false, "error": "Missing src"]); continue
                            }
                            if ClawsyFileManager.isGlobPattern(src) {
                                guard let matches = ClawsyFileManager.resolveGlob(baseDir: baseDir, pattern: src) else {
                                    results.append(["index": index, "op": opType, "success": false, "error": "Path traversal"]); continue
                                }
                                var successCount = 0; var errors: [[String: Any]] = []
                                for match in matches {
                                    if let fullPath = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: match) {
                                        switch ClawsyFileManager.deleteFile(at: fullPath) {
                                        case .success:
                                            successCount += 1
                                        case .failure(let error):
                                            errors.append(["file": match, "error": "Delete failed: \(error.description)"])
                                        }
                                    } else { errors.append(["file": match, "error": "Path traversal"]) }
                                }
                                results.append(["index": index, "op": opType, "success": errors.isEmpty, "matched": matches.count, "successCount": successCount, "errors": errors])
                            } else {
                                if let fullPath = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: src) {
                                    switch ClawsyFileManager.deleteFile(at: fullPath) {
                                    case .success:
                                        results.append(["index": index, "op": opType, "success": true])
                                    case .failure(let error):
                                        results.append(["index": index, "op": opType, "success": false, "error": error.description])
                                    }
                                } else { results.append(["index": index, "op": opType, "success": false, "error": "Path traversal"]) }
                            }
                        case "mkdir":
                            guard let dst = op["dst"] as? String else {
                                results.append(["index": index, "op": opType, "success": false, "error": "Missing dst"]); continue
                            }
                            if let fullPath = ClawsyFileManager.sandboxedPath(base: baseDir, relativePath: dst) {
                                switch ClawsyFileManager.createDirectory(at: fullPath) {
                                case .success:
                                    results.append(["index": index, "op": opType, "success": true])
                                case .failure(let error):
                                    results.append(["index": index, "op": opType, "success": false, "error": error.description])
                                }
                            } else { results.append(["index": index, "op": opType, "success": false, "error": "Path traversal"]) }
                        case "rename":
                            guard let path = op["path"] as? String, let newName = op["newName"] as? String else {
                                results.append(["index": index, "op": opType, "success": false, "error": "Missing path/newName"]); continue
                            }
                            switch ClawsyFileManager.renameFile(baseDir: baseDir, path: path, newName: newName) {
                            case .success: results.append(["index": index, "op": opType, "success": true])
                            case .failure(let e): results.append(["index": index, "op": opType, "success": false, "error": e.description])
                            }
                        case "stat":
                            guard let path = op["path"] as? String else {
                                results.append(["index": index, "op": opType, "success": false, "error": "Missing path"]); continue
                            }
                            let stat = ClawsyFileManager.statFile(baseDir: baseDir, relativePath: path)
                            if var dict = (try? JSONEncoder().encode(stat)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) {
                                dict["index"] = index
                                dict["op"] = opType
                                dict["success"] = dict["exists"] as? Bool ?? false
                                results.append(dict)
                            } else {
                                results.append(["index": index, "op": opType, "success": false, "error": "Failed to serialize stat"])
                            }
                        default:
                            results.append(["index": index, "op": opType, "success": false, "error": "Unknown operation: \(opType)"])
                        }
                    }
                    self.sendResponse(id: id, result: ["status": "ok", "results": results])
                }
            }
            if let expiry = filePermissionExpiry, expiry > Date() { executeBatch() } else { onFileSyncRequested?("batch (\(ops.count) ops)", "Batch file operations", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeBatch() }, { self.sendError(id: id, code: -1, message: "User denied batch operations") }) }
        default: sendError(id: id, code: -32601, message: "Method not found")
        }
    }
    
    private func isValidId(_ id: Any?) -> Bool { if let s = id as? String { return !s.isEmpty } else { return id is Int } }
    
    public func sendResponse(id: Any, result: Any) {
        if let idStr = id as? String {
            if idStr.hasPrefix("inv:") {
                let invocationId = String(idStr.dropFirst(4))
                send(json: [
                    "type": "req",
                    "id": "node.invoke.result-\(UUID().uuidString.prefix(8))",
                    "method": "node.invoke.result",
                    "params": ["id": invocationId, "nodeId": self.deviceId, "ok": true, "payload": result]
                ])
                return
            } else if idStr.hasPrefix("wrap:") {
                let actualIdStr = String(idStr.dropFirst(5))
                let actualId: Any = Int(actualIdStr) ?? actualIdStr
                send(json: ["type": "res", "id": actualId, "result": ["ok": true, "payload": result]])
                return
            }
        }
        guard isValidId(id) else { return }
        send(json: ["type": "res", "id": id, "result": result])
    }
    
    public func sendAck(id: Any) {
        if let idStr = id as? String, (idStr.hasPrefix("inv:") || idStr.hasPrefix("wrap:")) { return }
        guard isValidId(id) else { return }
        send(json: ["type": "ack", "id": id, "status": "processing"])
    }
    
    public func sendError(id: Any, code: Int, message: String) {
        if let idStr = id as? String {
            if idStr.hasPrefix("inv:") {
                let invocationId = String(idStr.dropFirst(4))
                send(json: [
                    "type": "req",
                    "id": "node.invoke.result-\(UUID().uuidString.prefix(8))",
                    "method": "node.invoke.result",
                    "params": ["id": invocationId, "nodeId": self.deviceId, "ok": false, "error": ["code": "\(code)", "message": message]]
                ])
                return
            } else if idStr.hasPrefix("wrap:") {
                let actualIdStr = String(idStr.dropFirst(5))
                let actualId: Any = Int(actualIdStr) ?? actualIdStr
                send(json: ["type": "res", "id": actualId, "result": ["ok": false, "error": ["code": code, "message": message]]])
                return
            }
        }
        guard isValidId(id) else { return }
        send(json: ["type": "res", "id": id, "error": ["code": code, "message": message]])
    }
    
    /// Send a screenshot via agent.request into clawsy-service (silent, no main chat delivery).
    public func sendScreenshot(base64: String, mimeType: String = "image/jpeg") {
        let deviceName = Host.current().localizedName ?? "Mac"

        // 1. Store in clawsy-service for agent context (silent)
        let storagePayload: [String: Any] = [
            "sessionKey": "clawsy-service",
            "message": "📸 Screenshot von \(deviceName)",
            "deliver": false,
            "receipt": false,
            "attachments": [
                [
                    "type": "image",
                    "mimeType": mimeType,
                    "fileName": "screenshot.jpg",
                    "content": base64
                ]
            ]
        ]
        let storageJSON = (try? JSONSerialization.data(withJSONObject: storagePayload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let storageFrame: [String: Any] = [
            "type": "req",
            "id": "event-\(UUID().uuidString.prefix(8))",
            "method": "node.event",
            "params": ["event": "agent.request", "payloadJSON": storageJSON]
        ]
        send(json: storageFrame)

        // 2. Deliver to main session (routed to Telegram/channel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let mainPayload: [String: Any] = [
                "sessionKey": "main",
                "message": "📸 Screenshot von Clawsy (\(deviceName))",
                "deliver": true,
                "receipt": false,
                "attachments": [
                    [
                        "type": "image",
                        "mimeType": mimeType,
                        "fileName": "screenshot.jpg",
                        "content": base64
                    ]
                ]
            ]
            let mainJSON = (try? JSONSerialization.data(withJSONObject: mainPayload))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let mainFrame: [String: Any] = [
                "type": "req",
                "id": "event-\(UUID().uuidString.prefix(8))",
                "method": "node.event",
                "params": ["event": "agent.request", "payloadJSON": mainJSON]
            ]
            self.send(json: mainFrame)
        }
    }

    /// Send an event routed to the dedicated clawsy-service session (silent, no main chat spam)
    /// Send a message to any session via agent.request.
    /// deliver=true → agent processes AND delivers reply via configured channel (e.g. Telegram)
    /// deliver=false → agent processes silently, no channel delivery
    public func sendDeeplink(message: String, sessionKey: String, deliver: Bool = false) {
        let params: [String: Any] = [
            "sessionKey": sessionKey,
            "message": message,
            "deliver": deliver,
            "receipt": false
        ]
        let frame: [String: Any] = [
            "type": "req",
            "id": "event-\(UUID().uuidString.prefix(8))",
            "method": "node.event",
            "params": [
                "event": "agent.request",
                "payloadJSON": (try? String(data: JSONSerialization.data(withJSONObject: params), encoding: .utf8)) ?? "{}"
            ]
        ]
        send(json: frame)
    }

    /// Send a message to clawsy-service session (silent, no Telegram delivery).
    public func sendServiceEvent(message: String, payload: [String: Any] = [:]) {
        sendDeeplink(message: message, sessionKey: "clawsy-service", deliver: false)
    }

    /// Send a camera photo: stores in clawsy-service (context) AND triggers main chat delivery.
    public func sendPhoto(base64: String, deviceName: String = "Kamera") {
        // 1. Store in clawsy-service for agent context (silent)
        let storagePayload: [String: Any] = [
            "sessionKey": "clawsy-service",
            "message": "📷 Kamerafoto von \(Host.current().localizedName ?? "Mac") (\(deviceName))",
            "deliver": false,
            "receipt": false,
            "attachments": [
                [
                    "type": "image",
                    "mimeType": "image/jpeg",
                    "fileName": "photo.jpg",
                    "content": base64
                ]
            ]
        ]
        let storageJSON = (try? JSONSerialization.data(withJSONObject: storagePayload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let storageFrame: [String: Any] = [
            "type": "req",
            "id": "event-\(UUID().uuidString.prefix(8))",
            "method": "node.event",
            "params": ["event": "agent.request", "payloadJSON": storageJSON]
        ]
        send(json: storageFrame)

        // 2. Trigger main session with the photo (delivered to Telegram)
        // Small delay to let storage frame settle first
        let mainPayload: [String: Any] = [
            "sessionKey": "main",
            "message": "📷 Kamerafoto von Clawsy (\(deviceName))",
            "deliver": true,
            "receipt": false,
            "attachments": [
                [
                    "type": "image",
                    "mimeType": "image/jpeg",
                    "fileName": "photo.jpg",
                    "content": base64
                ]
            ]
        ]
        let mainJSON = (try? JSONSerialization.data(withJSONObject: mainPayload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let mainFrame: [String: Any] = [
            "type": "req",
            "id": "event-\(UUID().uuidString.prefix(8))",
            "method": "node.event",
            "params": ["event": "agent.request", "payloadJSON": mainJSON]
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.send(json: mainFrame)
        }
    }

    public func sendEvent(kind: String, payload: Any) {
        // Enforce type: req with method: node.event to bypass 
        // current Gateway limitations accepting type: event frames after handshake.
        let frame: [String: Any] = [
            "type": "req",
            "id": "event-\(UUID().uuidString.prefix(8))",
            "method": "node.event",
            "params": [
                "event": kind,
                "payload": payload
            ]
        ]
        send(json: frame)
    }

    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json), let text = String(data: data, encoding: .utf8) else { return }
        // Starscream write must happen on the main thread
        if Thread.isMainThread {
            socket?.write(string: text)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.socket?.write(string: text)
            }
        }
    }
    
    private func base64UrlEncode(_ data: Data) -> String { return data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }

    // Telemetry Helpers
    public static func getTelemetry() -> [String: Any] {
        var telemetry: [String: Any] = [:]
        
        #if os(macOS)
        telemetry["deviceName"] = Host.current().localizedName ?? "Mac"
        telemetry["deviceModel"] = "Mac"
        
        // 1. Active App & Window
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            telemetry["activeApp"] = frontApp.localizedName ?? "Unknown"
            // Window title requires Accessibility permissions, usually needs a bit more code, 
            // but we can start with the app name.
        }

        // 2. Battery Status (IOKit)
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {
                if let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                   let maxCapacity = description[kIOPSMaxCapacityKey] as? Int {
                    telemetry["batteryLevel"] = Float(capacity) / Float(maxCapacity)
                    telemetry["isCharging"] = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                }
            }
        }

        // 3. System Load / Thermal
        telemetry["thermalState"] = ProcessInfo.processInfo.thermalState.rawValue // 0: nominal, 1: fair, 2: serious, 3: critical

        // 4. Mood Analysis (Derived)
        let now = Date()
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let currentAppName = frontApp.localizedName ?? ""
            if currentAppName != lastAppName {
                appSwitchCount += 1
                lastAppName = currentAppName
            }
        }
        
        let timeSinceLastCheck = now.timeIntervalSince(lastAppSwitchTime)
        let switchesPerMinute = Double(appSwitchCount) / (max(timeSinceLastCheck, 60) / 60.0)
        
        // Reset counter every 5 mins to keep it fresh
        if timeSinceLastCheck > 300 {
            appSwitchCount = 0
            lastAppSwitchTime = now
        }
        
        var moodScore = 70.0 // Default: Good/Neutral
        
        // Impact factors
        if switchesPerMinute > 5 { moodScore -= 20 } // Hectic app switching
        if ProcessInfo.processInfo.thermalState.rawValue >= 2 { moodScore -= 15 } // Thermal stress
        
        // Time/Day Context with Personalized Activity Profile
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now) // 1=Sun, 7=Sat
        
        // Update Activity Profile (Learning the user's "normal")
        NetworkManager.updateActivityProfile(hour: hour)
        
        // Check if current hour is "Normal" for this user
        if !NetworkManager.isNormalActivityHour(hour: hour) {
            moodScore -= 15 // Unusual activity time often implies pressure or urgency
        }
        
        if weekday == 1 || weekday == 7 { moodScore += 10 } // Weekend bonus
        
        telemetry["moodScore"] = max(0, min(100, moodScore))
        telemetry["appSwitchRate"] = switchesPerMinute
        telemetry["isUnusualHour"] = !NetworkManager.isNormalActivityHour(hour: hour)
        
        #elseif os(iOS)
        telemetry["deviceName"] = UIDevice.current.name
        telemetry["deviceModel"] = UIDevice.current.model
        UIDevice.current.isBatteryMonitoringEnabled = true
        telemetry["batteryLevel"] = UIDevice.current.batteryLevel
        telemetry["isCharging"] = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        #endif
        
        return telemetry
    }
    
    private static func updateActivityProfile(hour: Int) {
        var profile: [String: Int] = [:]
        if let data = SharedConfig.activityProfile.data(using: .utf8),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
            profile = existing
        }
        
        let key = String(hour)
        profile[key] = (profile[key] ?? 0) + 1
        
        let total = profile.values.reduce(0, +)
        if total > 500 {
            for (k, v) in profile { profile[k] = max(1, v / 2) }
        }
        
        if let nextData = try? JSONSerialization.data(withJSONObject: profile),
           let nextString = String(data: nextData, encoding: .utf8) {
            SharedConfig.activityProfile = nextString
        }
    }
    
    private static func isNormalActivityHour(hour: Int) -> Bool {
        guard let data = SharedConfig.activityProfile.data(using: .utf8),
              let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Int],
              !profile.isEmpty else {
            return true 
        }
        
        let total = profile.values.reduce(0, +)
        let count = profile[String(hour)] ?? 0
        return Double(count) / Double(total) > 0.02
    }
}
