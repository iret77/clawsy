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
typealias ClawsyImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias ClawsyImage = UIImage
#endif

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
    
    // Mood Tracking State
    private static var lastAppSwitchTime = Date()
    private static var appSwitchCount = 0
    private static var lastAppName = ""
    
    private var socket: WebSocket?
    private var connectionWatchdog: Timer?
    private var pairingTimeoutTimer: Timer?
    private var signingKey: Curve25519.Signing.PrivateKey?
    private var publicKey: Curve25519.Signing.PublicKey?
    
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
    
    // Internal Sync'd Settings
    private var serverHost: String { SharedConfig.serverHost }
    private var serverPort: String { SharedConfig.serverPort }
    private var serverToken: String { SharedConfig.serverToken }
    private var sshUser: String { SharedConfig.sharedDefaults.string(forKey: "sshUser") ?? "" }
    private var useSshFallback: Bool { 
        if SharedConfig.sharedDefaults.object(forKey: "useSshFallback") == nil { return true }
        return SharedConfig.sharedDefaults.bool(forKey: "useSshFallback") 
    }
    private var sharedFolderPath: String { SharedConfig.sharedDefaults.string(forKey: "sharedFolderPath") ?? "~/Documents/Clawsy" }
    
    // Device token for node pairing (per-host)
    private var deviceTokenKey: String { "clawsy_device_token_\(serverHost)" }
    private var deviceToken: String? {
        get { SharedConfig.sharedDefaults.string(forKey: deviceTokenKey) }
        set {
            if let val = newValue {
                SharedConfig.sharedDefaults.set(val, forKey: deviceTokenKey)
            } else {
                SharedConfig.sharedDefaults.removeObject(forKey: deviceTokenKey)
            }
            SharedConfig.sharedDefaults.synchronize()
        }
    }
    
    public override init() {
        super.init()
        // Try to load existing key or generate new one
        if let savedKeyData = SharedConfig.sharedDefaults.data(forKey: "nodePrivateKey"),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: savedKeyData) {
            self.signingKey = key
        } else {
            let newKey = Curve25519.Signing.PrivateKey()
            self.signingKey = newKey
            SharedConfig.sharedDefaults.set(newKey.rawRepresentation, forKey: "nodePrivateKey")
        }
        self.publicKey = self.signingKey?.publicKey
        setupNotifications()
        setupLocation()
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
        SharedConfig.save(host: host, port: port, token: token)
        if let user = sshUser { SharedConfig.sharedDefaults.set(user, forKey: "sshUser") }
        if let fback = fallback { SharedConfig.sharedDefaults.set(fback, forKey: "useSshFallback") }
        
        SharedConfig.sharedDefaults.synchronize()
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
            isUsingSshTunnel = false
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
            guard let self = self, !self.isConnected else { return }
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
    
    private func handleConnectionFailure(err: Error?) {
        DispatchQueue.main.async {
            self.connectionWatchdog?.invalidate()
            self.connectionWatchdog = nil
            
            self.socket?.delegate = nil
            self.socket?.disconnect()
            self.socket = nil

            let _ = err?.localizedDescription ?? "Unknown"
            
            #if os(macOS)
            if self.useSshFallback && !self.isUsingSshTunnel {
                self.startSshTunnel()
            } else {
                self.runDiagnostics(err: err)
            }
            #else
            self.runDiagnostics(err: err)
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
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.rawLog += "\n[SSH] Failed to start: \(error.localizedDescription)"
                    self.connectionStatus = "STATUS_SSH_FAILED"
                    self.isUsingSshTunnel = false
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
    }
    
    public func disconnect() {
        pairingTimeoutTimer?.invalidate()
        pairingTimeoutTimer = nil
        
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
        
        connectionAttemptCount = 0
        DispatchQueue.main.async {
            self.isConnected = false
            self.isHandshakeComplete = false
            self.connectionStatus = "STATUS_DISCONNECTED"
            self.rawLog += "\n[WSS] Disconnected"
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
                self.rawLog += "\n[WSS] Connected (headers: \(headers.count))"
                self.connectionWatchdog?.invalidate()
                self.connectionWatchdog = nil
                self.isConnected = true
                self.connectionStatus = "STATUS_CONNECTED"
                self.connectionAttemptCount = 0
            case .disconnected(let reason, let code):
                self.rawLog += "\n[WSS] Disconnected: \(reason) (code: \(code))"
                self.isConnected = false
                self.connectionStatus = "STATUS_DISCONNECTED"
            case .text(let string):
                self.rawLog += "\nIN: \(string)"
                self.handleMessage(string)
            case .error(let err):
                self.rawLog += "\n[WSS] Error: \(err?.localizedDescription ?? "nil")"
                self.isConnected = false
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

    private func checkServerAwareness() {
        let requestId = "discovery-\(UUID().uuidString.prefix(4))"
        let discoveryReq: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "file.get",
            "params": ["name": ".clawsy_version"]
        ]
        send(json: discoveryReq)
    }

    /// Called when task data changes (agentName, title, progress, statusText)
    public var onTaskUpdate: ((String, String, Double, String) -> Void)?

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Task updates via agent.status event (sent by agent via file.set → .agent_status.json)
        // Primary channel: Shared Folder (.agent_status.json) watched by FileWatcher
        // This handler is kept for direct WebSocket delivery as fallback
        if let kind = json["kind"] as? String, kind == "agent.status",
           let payload = json["payload"] as? [String: Any] {
            let agent = payload["agentName"] as? String ?? "Unknown"
            let title = payload["title"] as? String ?? ""
            let progress = payload["progress"] as? Double ?? 0.0
            let status = payload["statusText"] as? String ?? ""
            onTaskUpdate?(agent, title, progress, status)
        }

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
            self.connectionStatus = "STATUS_PAIRING_PENDING"
            self.rawLog += "\n[PAIR] Pairing pending – awaiting admin approval"
            return
        }
        
        if event == "node.pair.resolved" {
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
                if rid.hasPrefix("discovery-") {
                    if let result = json["result"] as? [String: Any],
                       let contentB64 = result["content"] as? String,
                       let data = Data(base64Encoded: contentB64),
                       let versionStr = String(data: data, encoding: .utf8) {
                        self.isServerClawsyAware = true
                        self.serverVersion = versionStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        self.isServerClawsyAware = false
                    }
                    return
                }
                
                if rid == "1" {
                let payload = json["payload"] as? [String: Any]
                if payload?["type"] as? String == "hello-ok" || json["result"] != nil {
                     self.isHandshakeComplete = true
                     self.connectionStatus = isUsingSshTunnel ? "STATUS_ONLINE_PAIRED_SSH" : "STATUS_ONLINE_PAIRED"
                     self.onHandshakeComplete?()
                     
                     // Store deviceToken from hello-ok if present
                     if let result = json["result"] as? [String: Any],
                        let auth = result["auth"] as? [String: Any],
                        let dt = auth["deviceToken"] as? String {
                         self.deviceToken = dt
                     } else if let p = payload,
                               let auth = p["auth"] as? [String: Any],
                               let dt = auth["deviceToken"] as? String {
                         self.deviceToken = dt
                     }
                     
                     // Trigger Discovery Check
                     self.checkServerAwareness()
                     
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
                     // Extract requestId and send pairing request
                     let details = errorObj["details"] as? [String: Any]
                     let requestId = details?["requestId"] as? String ?? ""
                     self.connectionStatus = "STATUS_PAIRING"
                     
                     // Cancel the connection watchdog – pairing can take minutes
                     self.connectionWatchdog?.invalidate()
                     self.connectionWatchdog = nil
                     
                     // Start a 5-minute pairing timeout as safety net
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
                          (errorCode == "AUTH_TOKEN_MISMATCH" || errorCode == "INVALID_REQUEST") {
                     // Stored deviceToken is stale (gateway restarted). Clear it and retry with master token.
                     self.rawLog += "\n[AUTH] Token mismatch – clearing deviceToken, retrying with master token"
                     self.deviceToken = nil
                     self.disconnect()
                     DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                         self.connect()
                     }
                } else if json["error"] != nil {
                     self.isHandshakeComplete = false
                     self.connectionStatus = "STATUS_HANDSHAKE_FAILED"
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

    private func performHandshake(nonce: String) {
        guard let signingKey = signingKey, let publicKey = publicKey else { return }
        let tsMs = Int64(Date().timeIntervalSince1970 * 1000)
        let deviceId = self.deviceId
        
        // Protocol V2 components: version, deviceId, clientId, role, mode, clientVersion, ts, token, nonce
        // Note: clientId MUST be 'openclaw-macos' (or similar recognized id) for standard Gateway logic.
        let authToken = deviceToken ?? serverToken
        let components = ["v2", deviceId, "openclaw-macos", "node", "node", "", String(tsMs), authToken, nonce]
        let payloadString = components.joined(separator: "|")
        guard let payloadData = payloadString.data(using: .utf8) else { return }
        guard let signature = try? signingKey.signature(for: payloadData) else { return }
        let pubKeyB64 = base64UrlEncode(publicKey.rawRepresentation)
        let sigB64 = base64UrlEncode(signature)
        
        #if os(macOS)
        let platform = "macos"
        #elseif os(iOS)
        let platform = "ios"
        #elseif os(tvOS)
        let platform = "tvos"
        #else
        let platform = "unknown"
        #endif
        
        let connectReq: [String: Any] = [
            "type": "req", "id": "1", "method": "connect",
            "params": [
                "minProtocol": 3, "maxProtocol": 3,
                "client": ["id": "openclaw-\(platform)", "version": SharedConfig.versionDisplay, "platform": platform, "mode": "node"],
                "role": "node", "caps": ["clipboard", "screen", "camera", "file", "location"], 
                "commands": ["clipboard.read", "clipboard.write", "screen.capture", "camera.list", "camera.snap", "file.list", "file.get", "file.set", "location.get", "location.start", "location.stop", "location.add_smart"],
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
            let subPath = params["subPath"] as? String ?? ""
            DispatchQueue.global(qos: .userInitiated).async {
                let files = ClawsyFileManager.listFiles(at: baseDir, subPath: subPath)
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
            let fullPath = (baseDir as NSString).appendingPathComponent(name)
            self.sendAck(id: id)
            let executeGet = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .clawsy, comment: ""), body: String(format: NSLocalizedString("NOTIFICATION_BODY_DOWNLOADING", bundle: .clawsy, comment: ""), name), isAuto: (self.filePermissionExpiry != nil && self.filePermissionExpiry! > Date()))
                DispatchQueue.global(qos: .userInitiated).async {
                    if let b64 = ClawsyFileManager.readFile(at: fullPath) { self.sendResponse(id: id, result: ["content": b64, "name": name]) } else { self.sendError(id: id, code: -32000, message: "Failed to read file") }
                }
            }
            if let expiry = filePermissionExpiry, expiry > Date() { executeGet() } else { onFileSyncRequested?(name, "Download", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeGet() }, { self.sendError(id: id, code: -1, message: "User denied file access") }) }
        case "file.set":
            guard let name = params["name"] as? String, let content = params["content"] as? String else { sendError(id: id, code: -32602, message: "Missing 'name' or 'content' parameter"); return }
            let fullPath = (baseDir as NSString).appendingPathComponent(name)
            self.sendAck(id: id)
            let executeSet = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .clawsy, comment: ""), body: String(format: NSLocalizedString("NOTIFICATION_BODY_UPLOADING", bundle: .clawsy, comment: ""), name), isAuto: (self.filePermissionExpiry != nil && self.filePermissionExpiry! > Date()))
                DispatchQueue.global(qos: .userInitiated).async {
                    if ClawsyFileManager.writeFile(at: fullPath, base64Content: content) { self.sendResponse(id: id, result: ["status": "ok", "name": name]) } else { self.sendError(id: id, code: -32000, message: "Failed to write file") }
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
        case "file.delete":
            guard let name = params["name"] as? String else { sendError(id: id, code: -32602, message: "Missing 'name' parameter"); return }
            let fullPath = (baseDir as NSString).appendingPathComponent(name)
            self.sendAck(id: id)
            let executeDelete = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .clawsy, comment: ""), body: "Deleted: \(name)", isAuto: (self.filePermissionExpiry != nil && self.filePermissionExpiry! > Date()))
                DispatchQueue.global(qos: .userInitiated).async {
                    if ClawsyFileManager.deleteFile(at: fullPath) { self.sendResponse(id: id, result: ["status": "ok", "name": name]) } else { self.sendError(id: id, code: -32000, message: "Failed to delete file") }
                }
            }
            if let expiry = filePermissionExpiry, expiry > Date() { executeDelete() } else { onFileSyncRequested?(name, "Delete", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeDelete() }, { self.sendError(id: id, code: -1, message: "User denied file delete") }) }
        case "file.rename":
            guard let name = params["name"] as? String, let newName = params["newName"] as? String else { sendError(id: id, code: -32602, message: "Missing 'name' or 'newName' parameter"); return }
            let fullPath = (baseDir as NSString).appendingPathComponent(name)
            self.sendAck(id: id)
            let executeRename = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .clawsy, comment: ""), body: "Renamed: \(name) -> \(newName)", isAuto: (self.filePermissionExpiry != nil && self.filePermissionExpiry! > Date()))
                DispatchQueue.global(qos: .userInitiated).async {
                    if ClawsyFileManager.renameFile(at: fullPath, to: newName) { self.sendResponse(id: id, result: ["status": "ok", "name": newName]) } else { self.sendError(id: id, code: -32000, message: "Failed to rename file") }
                }
            }
            if let expiry = filePermissionExpiry, expiry > Date() { executeRename() } else { onFileSyncRequested?(name, "Rename to \(newName)", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeRename() }, { self.sendError(id: id, code: -1, message: "User denied file rename") }) }
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
        let payload: [String: Any] = [
            "sessionKey": "clawsy-service",
            "message": "📸 Screenshot von \(Host.current().localizedName ?? "Mac")",
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
        let payloadJSON = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let frame: [String: Any] = [
            "type": "req",
            "id": "event-\(UUID().uuidString.prefix(8))",
            "method": "node.event",
            "params": [
                "event": "agent.request",
                "payloadJSON": payloadJSON
            ]
        ]
        send(json: frame)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            send(json: mainFrame)
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
