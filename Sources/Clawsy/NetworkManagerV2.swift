import Foundation
import Starscream
import CryptoKit
import AppKit
import SwiftUI
import UserNotifications
import os.log

// MARK: - NetworkManagerV2 (Native Node Protocol)

@available(macOS 13.0, *)
class NetworkManagerV2: NSObject, ObservableObject, WebSocketDelegate, UNUserNotificationCenterDelegate {
    private let logger = OSLog(subsystem: "ai.clawsy", category: "Network")
    
    @Published var isConnected = false
    @Published var connectionStatus = "STATUS_DISCONNECTED"
    @Published var connectionAttemptCount = 0
    @Published var lastMessage = ""
    @Published var rawLog = ""
    
    private var socket: WebSocket?
    private var connectionWatchdog: Timer?
    private var signingKey: Curve25519.Signing.PrivateKey?
    private var publicKey: Curve25519.Signing.PublicKey?
    
    // SSH Tunnel Management
    private var sshProcess: Process?
    private var isUsingSshTunnel = false
    
    // Callbacks for UI/Logic
    var onScreenshotRequested: ((Bool, String) -> Void)?
    var onClipboardReadRequested: ((String) -> Void)?
    var onClipboardWriteRequested: ((String, String) -> Void)?
    var onFileSyncRequested: ((String, String, @escaping (TimeInterval?) -> Void, @escaping () -> Void) -> Void)?
    
    // Permission Tracking
    private var filePermissionExpiry: Date?
    
    // Internal Sync'd Settings
    private var serverHost: String { UserDefaults.standard.string(forKey: "serverHost") ?? "agenthost" }
    private var serverPort: String { UserDefaults.standard.string(forKey: "serverPort") ?? "18789" }
    private var serverToken: String { UserDefaults.standard.string(forKey: "serverToken") ?? "" }
    private var sshUser: String { UserDefaults.standard.string(forKey: "sshUser") ?? "" }
    private var useSshFallback: Bool { UserDefaults.standard.bool(forKey: "useSshFallback") }
    private var sharedFolderPath: String { UserDefaults.standard.string(forKey: "sharedFolderPath") ?? "~/Documents/Clawsy" }
    
    override init() {
        super.init()
        self.signingKey = Curve25519.Signing.PrivateKey()
        self.publicKey = self.signingKey?.publicKey
        setupNotifications()
    }
    
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        let revokeAction = UNNotificationAction(identifier: "REVOKE_PERMISSION",
                                              title: NSLocalizedString("REVOKE_PERMISSION", comment: ""),
                                              options: [.destructive])
        
        let category = UNNotificationCategory(identifier: "FILE_SYNC",
                                             actions: [revokeAction],
                                             intentIdentifiers: [],
                                             options: [])
        
        center.setNotificationCategories([category])
        
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                os_log("Notification permission error: %{public}@", log: self.logger, type: .error, error.localizedDescription)
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
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
    
    func configure(host: String, port: String, token: String) {
        // Sync to UserDefaults as we don't use @AppStorage here
        UserDefaults.standard.set(host, forKey: "serverHost")
        UserDefaults.standard.set(port, forKey: "serverPort")
        UserDefaults.standard.set(token, forKey: "serverToken")
        // Ensure values are synchronized to disk
        UserDefaults.standard.synchronize()
        os_log("Configured with Host: %{public}@, Port: %{public}@", log: logger, type: .info, host, port)
    }

    func connect() {
        // Refresh values from disk before connecting
        UserDefaults.standard.synchronize()
        
        let host = serverHost
        let token = serverToken
        
        guard !host.isEmpty, !token.isEmpty else {
            DispatchQueue.main.async {
                self.connectionStatus = "STATUS_DISCONNECTED"
                self.rawLog += "\n[WSS] Error: Missing Host or Token"
            }
            return
        }
        
        // If this is a fresh start (not a programmed retry), reset tunnel state
        if connectionAttemptCount == 0 {
            isUsingSshTunnel = false
        }
        
        connectionAttemptCount += 1
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "STATUS_CONNECTING"
            self.rawLog += "\n[WSS] Connection Attempt #\(self.connectionAttemptCount) (Tunnel: \(self.isUsingSshTunnel))"
        }
        
        // Ensure old socket is cleaned up before creating a new one
        socket?.delegate = nil
        socket?.disconnect()
        socket = nil
        
        var targetUrlStr: String
        if isUsingSshTunnel {
            // Force ws for local tunnel
            targetUrlStr = "ws://127.0.0.1:18790"
            os_log("CONNECT: Using SSH Tunnel target: %{public}@", log: logger, type: .info, targetUrlStr)
            DispatchQueue.main.async {
                self.rawLog += "\n[WSS] Switching to Tunnel URL: \(targetUrlStr)"
            }
        } else {
            let scheme = (host.contains("localhost") || host.contains("127.0.0.1")) ? "ws" : "wss"
            targetUrlStr = "\(scheme)://\(host):\(serverPort)"
            os_log("CONNECT: Using direct target: %{public}@", log: logger, type: .info, targetUrlStr)
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
        os_log("Attempting connection to %{public}@", log: logger, type: .info, url.absoluteString)
        DispatchQueue.main.async {
            self.rawLog += "\n[WSS] Connecting to \(url.absoluteString)..."
        }
        
        // Start Watchdog (Manual 5s Timer)
        connectionWatchdog?.invalidate()
        connectionWatchdog = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConnected else { return }
            os_log("Connection watchdog fired (Timeout)", log: self.logger, type: .error)
            DispatchQueue.main.async {
                self.rawLog += "\n[WSS] Watchdog Timeout (5s)"
                self.handleConnectionFailure(error: NSError(domain: "ai.clawsy", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection Timeout (Watchdog)"]))
            }
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // Aggressive timeout
        
        let newSocket = WebSocket(request: request)
        newSocket.delegate = self
        self.socket = newSocket
        self.socket?.connect()
    }
    
    private func handleConnectionFailure(error: Error?) {
        DispatchQueue.main.async {
            self.connectionWatchdog?.invalidate()
            self.connectionWatchdog = nil
            
            // Clean up socket on failure
            self.socket?.delegate = nil
            self.socket?.disconnect()
            self.socket = nil

            let errDesc = error?.localizedDescription ?? "Unknown"
            os_log("Connection failure: %{public}@", log: self.logger, type: .error, errDesc)
            
            // Check for SSL/Handshake specific hints
            if errDesc.lowercased().contains("ssl") || errDesc.lowercased().contains("certificate") || errDesc.lowercased().contains("handshake") {
                self.rawLog += "\n[WSS] Possible SSL/Handshake error detected."
            }
            
            let fallbackEnabled = self.useSshFallback
            let alreadyInTunnel = self.isUsingSshTunnel
            
            self.rawLog += "\n[WSS] Connection Error: \(errDesc)"
            self.rawLog += "\n[WSS] State: useSshFallback=\(fallbackEnabled), isUsingSshTunnel=\(alreadyInTunnel)"
            
            if fallbackEnabled && !alreadyInTunnel {
                self.startSshTunnel()
            } else {
                // If we are already in a tunnel and it fails, or no fallback
                self.runDiagnostics(error: error)
            }
        }
    }
    
    private func startSshTunnel() {
        // Ensure we are on main thread for rawLog updates
        DispatchQueue.main.async {
            self.rawLog += "\n[SSH] Entering startSshTunnel..."
            
            let host = self.serverHost
            let user = self.sshUser
            let port = self.serverPort
            
            guard !user.isEmpty else {
                os_log("SSH User is missing. Cannot start tunnel.", log: self.logger, type: .error)
                self.connectionStatus = "STATUS_SSH_USER_MISSING"
                self.rawLog += "\n[SSH] Error: SSH User is missing"
                return
            }
            
            let remoteTarget = "\(user)@\(host)"
            let tunnelSpec = "18790:127.0.0.1:\(port)"
            
            os_log("Initiating SSH Tunnel Fallback for %{public}@...", log: self.logger, type: .info, host)
            self.connectionStatus = "STATUS_STARTING_SSH"
            self.rawLog += "\n[SSH] Starting SSH process..."
            self.rawLog += "\n[SSH] Command: ssh -NT -L \(tunnelSpec) \(remoteTarget)"
            
            // Kill existing tunnel if any
            self.sshProcess?.terminate()
            self.isUsingSshTunnel = false
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            
            // -o ExitOnForwardFailure=yes is CRITICAL to know if the tunnel actually worked
            process.arguments = [
                "-NT", 
                "-L", tunnelSpec, 
                remoteTarget, 
                "-o", "ConnectTimeout=10", 
                "-o", "BatchMode=yes",
                "-o", "StrictHostKeyChecking=no",
                "-o", "ExitOnForwardFailure=yes"
            ]
            
            do {
                try process.run()
                self.sshProcess = process
                let pid = process.processIdentifier
                
                self.rawLog += "\n[SSH] SSH process started (PID: \(pid))"
                
                // Give SSH a moment to establish the encrypted link
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if let proc = self.sshProcess, proc.isRunning {
                        os_log("SSH Tunnel established successfully.", log: self.logger, type: .info)
                        self.isUsingSshTunnel = true
                        self.rawLog += "\n[SSH] Tunnel established."
                        self.connect() // This will now use Attempt 2 with the tunnel URL
                    } else {
                        os_log("SSH Tunnel failed to stay alive.", log: self.logger, type: .error)
                        self.isUsingSshTunnel = false
                        self.connectionStatus = "STATUS_SSH_FAILED"
                        self.rawLog += "\n[SSH] Error: Tunnel failed to stay alive."
                    }
                }
            } catch {
                os_log("Failed to launch SSH process: %{public}@", log: self.logger, type: .error, error.localizedDescription)
                self.connectionStatus = "STATUS_SSH_FAILED"
                self.isUsingSshTunnel = false
                self.rawLog += "\n[SSH] Launch Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func runDiagnostics(error: Error?) {
        let errorDesc = error?.localizedDescription ?? "Unknown error"
        if errorDesc.contains("refused") {
            connectionStatus = "STATUS_OFFLINE_REFUSED"
        } else if errorDesc.contains("timed out") {
            connectionStatus = "STATUS_OFFLINE_TIMEOUT"
        } else {
            connectionStatus = "STATUS_ERROR"
        }
    }
    
    func disconnect() {
        socket?.delegate = nil
        socket?.disconnect()
        socket = nil
        
        sshProcess?.terminate()
        sshProcess = nil
        isUsingSshTunnel = false
        
        connectionAttemptCount = 0
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "STATUS_DISCONNECTED"
            self.rawLog += "\n[WSS] Disconnected and Tunnel closed."
        }
    }
    
    // MARK: - WebSocketDelegate
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch event {
            case .connected(_):
                self.connectionWatchdog?.invalidate()
                self.connectionWatchdog = nil
                self.isConnected = true
                self.connectionStatus = "STATUS_CONNECTED"
                self.connectionAttemptCount = 0
                os_log("Websocket is connected", log: self.logger, type: .info)
                
            case .disconnected(let reason, let code):
                self.isConnected = false
                self.connectionStatus = "STATUS_DISCONNECTED"
                os_log("Websocket is disconnected: %{public}@ code: %d", log: self.logger, type: .info, reason, code)
                
            case .text(let string):
                self.handleMessage(string)
                
            case .error(let error):
                self.isConnected = false
                self.handleConnectionFailure(error: error)
                os_log("Websocket error: %{public}@", log: self.logger, type: .error, error?.localizedDescription ?? "Unknown")
                
            default: break
            }
        }
    }
    
    // MARK: - Protocol Logic
    
    private func handleMessage(_ text: String) {
        os_log("RAW INBOUND: %{public}@", log: logger, type: .default, text)
        
        DispatchQueue.main.async {
            self.rawLog += "\nIN: \(text)"
        }
        
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        if let event = json["event"] as? String, event == "connect.challenge" {
            if let payload = json["payload"] as? [String: Any], let nonce = payload["nonce"] as? String {
                performHandshake(nonce: nonce)
            }
            return
        }
        
        if let id = json["id"] as? String, id == "1" {
            let isResponse = (json["type"] as? String == "res" || json["type"] as? String == "response")
            let payload = json["payload"] as? [String: Any]
            
            if isResponse && (payload?["type"] as? String == "hello-ok" || json["result"] != nil) {
                 self.connectionStatus = isUsingSshTunnel ? "STATUS_ONLINE_PAIRED_SSH" : "STATUS_ONLINE_PAIRED"
            } else if json["error"] != nil {
                 self.connectionStatus = "STATUS_HANDSHAKE_FAILED"
            }
            return
        }
        
        if let type = json["type"] as? String, type == "req",
           let id = json["id"] as? String,
           let method = json["method"] as? String, method == "node.invoke",
           let params = json["params"] as? [String: Any],
           let command = params["command"] as? String {
            
            handleCommand(id: id, command: command, params: params)
            return
        }
    }
    
    private func performHandshake(nonce: String) {
        guard let signingKey = signingKey, let publicKey = publicKey else { return }
        
        let tsMs = Int64(Date().timeIntervalSince1970 * 1000)
        let pubKeyData = publicKey.rawRepresentation
        let deviceId = SHA256.hash(data: pubKeyData).map { String(format: "%02x", $0) }.joined()
        
        let components = ["v2", deviceId, "openclaw-macos", "node", "node", "", String(tsMs), serverToken, nonce]
        let payloadString = components.joined(separator: "|")
        
        guard let payloadData = payloadString.data(using: .utf8) else { return }
        guard let signature = try? signingKey.signature(for: payloadData) else { return }
        
        let pubKeyB64 = base64UrlEncode(pubKeyData)
        let sigB64 = base64UrlEncode(signature)
        
        let connectReq: [String: Any] = [
            "type": "req",
            "id": "1",
            "method": "connect",
            "params": [
                "minProtocol": 3, "maxProtocol": 3,
                "client": ["id": "openclaw-macos", "version": "0.2.0", "platform": "macos", "mode": "node"],
                "role": "node", "caps": ["clipboard", "screen", "camera", "file"], 
                "commands": ["clipboard.read", "clipboard.write", "screen.capture", "camera.list", "camera.snap", "file.list", "file.get", "file.set"],
                "permissions": ["clipboard.read": true, "clipboard.write": true],
                "auth": ["token": serverToken],
                "device": ["id": deviceId, "publicKey": pubKeyB64, "signature": sigB64, "signedAt": tsMs, "nonce": nonce]
            ]
        ]
        send(json: connectReq)
    }
    
    private func resolveSharedPath(_ path: String) -> String {
        return path.replacingOccurrences(of: "~", with: NSHomeDirectory())
    }
    
    private func handleCommand(id: String, command: String, params: [String: Any]) {
        os_log("Handling command: %{public}@", log: logger, type: .info, command)
        
        let baseDir = resolveSharedPath(sharedFolderPath)
        
        switch command {
        case "screen.capture":
            let interactive = params["interactive"] as? Bool ?? false
            onScreenshotRequested?(interactive, id)
            
        case "camera.list":
            let cameras = CameraManager.listCameras()
            sendResponse(id: id, result: ["cameras": cameras])
            
        case "camera.snap":
            let deviceId = params["deviceId"] as? String
            CameraManager.takePhoto(deviceId: deviceId) { b64 in
                if let b64 = b64 {
                    self.sendResponse(id: id, result: ["content": b64])
                } else {
                    self.sendError(id: id, code: -32000, message: "Camera capture failed")
                }
            }
            
        case "clipboard.read":
            onClipboardReadRequested?(id)
            
        case "clipboard.write":
            if let content = params["text"] as? String {
                onClipboardWriteRequested?(content, id)
            } else {
                sendError(id: id, code: -32602, message: "Missing 'text' parameter")
            }
            
        case "file.list":
            let files = ClawsyFileManager.listFiles(at: baseDir)
            let result = files.map { ["name": $0.name, "isDirectory": $0.isDirectory, "size": $0.size, "modified": $0.modified.timeIntervalSince1970] }
            sendResponse(id: id, result: ["files": result, "path": sharedFolderPath])
            
        case "file.get":
            guard let name = params["name"] as? String else {
                sendError(id: id, code: -32602, message: "Missing 'name' parameter")
                return
            }
            let fullPath = (baseDir as NSString).appendingPathComponent(name)
            
            let executeGet = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", comment: ""), 
                                body: String(format: NSLocalizedString("NOTIFICATION_BODY_DOWNLOADING", comment: ""), name), 
                                isAuto: (self.filePermissionExpiry != nil && self.filePermissionExpiry! > Date()))
                if let b64 = ClawsyFileManager.readFile(at: fullPath) {
                    self.sendResponse(id: id, result: ["content": b64, "name": name])
                } else {
                    self.sendError(id: id, code: -32000, message: "Failed to read file")
                }
            }
            
            if let expiry = filePermissionExpiry, expiry > Date() {
                executeGet()
            } else {
                onFileSyncRequested?(name, "Download", { duration in
                    if let duration = duration {
                        self.filePermissionExpiry = Date().addingTimeInterval(duration)
                    }
                    executeGet()
                }, {
                    self.sendError(id: id, code: -1, message: "User denied file access")
                })
            }
            
        case "file.set":
            guard let name = params["name"] as? String, let content = params["content"] as? String else {
                sendError(id: id, code: -32602, message: "Missing 'name' or 'content' parameter")
                return
            }
            let fullPath = (baseDir as NSString).appendingPathComponent(name)
            
            let executeSet = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", comment: ""), 
                                body: String(format: NSLocalizedString("NOTIFICATION_BODY_UPLOADING", comment: ""), name), 
                                isAuto: (self.filePermissionExpiry != nil && self.filePermissionExpiry! > Date()))
                if ClawsyFileManager.writeFile(at: fullPath, base64Content: content) {
                    self.sendResponse(id: id, result: ["status": "ok", "name": name])
                } else {
                    self.sendError(id: id, code: -32000, message: "Failed to write file")
                }
            }
            
            if let expiry = filePermissionExpiry, expiry > Date() {
                executeSet()
            } else {
                onFileSyncRequested?(name, "Upload", { duration in
                    if let duration = duration {
                        self.filePermissionExpiry = Date().addingTimeInterval(duration)
                    }
                    executeSet()
                }, {
                    self.sendError(id: id, code: -1, message: "User denied file write")
                })
            }
            
        default:
            sendError(id: id, code: -32601, message: "Method not found")
        }
    }
    
    // MARK: - Response Helpers
    
    func sendResponse(id: String, result: Any) {
        send(json: ["type": "res", "id": id, "result": result])
    }
    
    func sendError(id: String, code: Int, message: String) {
        send(json: ["type": "res", "id": id, "error": ["code": code, "message": message]])
    }
    
    func sendEvent(kind: String, payload: Any) {
        send(json: ["type": "event", "event": "node.event", "payload": ["kind": kind, "data": payload, "ts": Int64(Date().timeIntervalSince1970 * 1000)]])
    }

    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        
        DispatchQueue.main.async {
            self.rawLog += "\nOUT: \(text)"
        }
        
        socket?.write(string: text)
    }
    
    private func base64UrlEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
