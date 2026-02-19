import Foundation
import Starscream
import CryptoKit
import SwiftUI
import UserNotifications
import os.log

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
    
    // Mood Tracking State
    private static var lastAppSwitchTime = Date()
    private static var appSwitchCount = 0
    private static var lastAppName = ""
    
    private var socket: WebSocket?
    private var connectionWatchdog: Timer?
    private var signingKey: Curve25519.Signing.PrivateKey?
    private var publicKey: Curve25519.Signing.PublicKey?
    
    // SSH Tunnel Management (macOS only)
    #if os(macOS)
    private var sshProcess: Process?
    #endif
    private var isUsingSshTunnel = false
    
    // Callbacks for UI/Logic
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
    
    public override init() {
        super.init()
        self.signingKey = Curve25519.Signing.PrivateKey()
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
                                              title: NSLocalizedString("REVOKE_PERMISSION", bundle: .module, comment: ""),
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
            targetUrlStr = "ws://127.0.0.1:18790"
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
        connectionWatchdog = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConnected else { return }
            DispatchQueue.main.async {
                self.rawLog += "\n[WSS] Watchdog Timeout (5s)"
                self.handleConnectionFailure(err: NSError(domain: "ai.clawsy", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection Timeout (Watchdog)"]))
            }
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
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
    private func startSshTunnel() {
        DispatchQueue.main.async {
            let host = self.serverHost
            let user = self.sshUser
            let port = self.serverPort
            
            guard !user.isEmpty else {
                self.connectionStatus = "STATUS_SSH_USER_MISSING"
                return
            }
            
            let remoteTarget = "\(user)@\(host)"
            let tunnelSpec = "18790:127.0.0.1:\(port)"
            
            self.connectionStatus = "STATUS_STARTING_SSH"
            self.sshProcess?.terminate()
            
            let killProcess = Process()
            killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            killProcess.arguments = ["bash", "-c", "lsof -t -i:18790 | xargs kill -9"]
            try? killProcess.run()
            killProcess.waitUntilExit()

            self.isUsingSshTunnel = false
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = ["-NT", "-L", tunnelSpec, remoteTarget, "-o", "ConnectTimeout=10", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no", "-o", "ExitOnForwardFailure=yes"]
            
            do {
                try process.run()
                self.sshProcess = process
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    if let proc = self.sshProcess, proc.isRunning {
                        self.isUsingSshTunnel = true
                        self.connect()
                    } else {
                        self.isUsingSshTunnel = false
                        self.connectionStatus = "STATUS_SSH_FAILED"
                    }
                }
            } catch {
                self.connectionStatus = "STATUS_SSH_FAILED"
                self.isUsingSshTunnel = false
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
        socket?.delegate = nil
        socket?.disconnect()
        socket = nil
        
        #if os(macOS)
        sshProcess?.terminate()
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
            if self.rawLog.isEmpty || !self.rawLog.contains("Clawsy v0.2.4") {
                let dateStr = ISO8601DateFormatter().string(from: Date())
                let header = "[LOG START] \(dateStr) | Clawsy v0.2.4\n----------------------------------------\n"
                self.rawLog = header + self.rawLog
            }
            
            switch event {
            case .connected(_):
                self.connectionWatchdog?.invalidate()
                self.connectionWatchdog = nil
                self.isConnected = true
                self.connectionStatus = "STATUS_CONNECTED"
                self.connectionAttemptCount = 0
            case .disconnected(_, _):
                self.isConnected = false
                self.connectionStatus = "STATUS_DISCONNECTED"
            case .text(let string):
                self.rawLog += "\nIN: \(string)"
                self.handleMessage(string)
            case .error(let err):
                self.isConnected = false
                self.handleConnectionFailure(err: err)
            default: break
            }
        }
    }
    
    // One-Shot Send Logic
    private var oneShotPayload: (String, Any)?
    private var oneShotCompletion: ((Bool) -> Void)?

    public func sendOneShot(kind: String, payload: Any, completion: @escaping (Bool) -> Void) {
        self.oneShotPayload = (kind, payload)
        self.oneShotCompletion = completion
        
        // If already connected and paired, send immediately
        if isConnected && isHandshakeComplete {
            sendEvent(kind: kind, payload: payload)
            completion(true)
            return
        }
        
        // Otherwise, connect and wait for handshake
        self.connect()
        
        // Timeout for one-shot
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if self.oneShotPayload != nil {
                self.oneShotCompletion?(false)
                self.oneShotPayload = nil
                self.disconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

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
            if let rid = rawId as? String, rid == "1" {
                let payload = json["payload"] as? [String: Any]
                if payload?["type"] as? String == "hello-ok" || json["result"] != nil {
                     self.isHandshakeComplete = true
                     self.connectionStatus = isUsingSshTunnel ? "STATUS_ONLINE_PAIRED_SSH" : "STATUS_ONLINE_PAIRED"
                     
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
                } else if json["error"] != nil {
                     self.isHandshakeComplete = false
                     self.connectionStatus = "STATUS_HANDSHAKE_FAILED"
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
        let components = ["v2", deviceId, "openclaw-macos", "node", "node", "", String(tsMs), serverToken, nonce]
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
                "client": ["id": "openclaw-\(platform)", "version": "0.2.4", "platform": platform, "mode": "node"],
                "role": "node", "caps": ["clipboard", "screen", "camera", "file", "location"], 
                "commands": ["clipboard.read", "clipboard.write", "screen.capture", "camera.list", "camera.snap", "file.list", "file.get", "file.set", "location.get", "location.start", "location.stop", "location.add_smart"],
                "permissions": ["clipboard.read": true, "clipboard.write": true],
                "auth": ["token": serverToken],
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
            DispatchQueue.global(qos: .userInitiated).async {
                let files = ClawsyFileManager.listFiles(at: baseDir)
                let result = files.map { ["name": $0.name, "isDirectory": $0.isDirectory, "size": $0.size, "modified": $0.modified.timeIntervalSince1970] }
                self.sendResponse(id: id, result: ["files": result, "path": self.sharedFolderPath])
            }
        case "file.get":
            guard let name = params["name"] as? String else { sendError(id: id, code: -32602, message: "Missing 'name' parameter"); return }
            let fullPath = (baseDir as NSString).appendingPathComponent(name)
            self.sendAck(id: id)
            let executeGet = {
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .module, comment: ""), body: String(format: NSLocalizedString("NOTIFICATION_BODY_DOWNLOADING", bundle: .module, comment: ""), name), isAuto: (self.filePermissionExpiry != nil && self.filePermissionExpiry! > Date()))
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
                self.notifyAction(title: NSLocalizedString("NOTIFICATION_TITLE", bundle: .module, comment: ""), body: String(format: NSLocalizedString("NOTIFICATION_BODY_UPLOADING", bundle: .module, comment: ""), name), isAuto: (self.filePermissionExpiry != nil && self.filePermissionExpiry! > Date()))
                DispatchQueue.global(qos: .userInitiated).async {
                    if ClawsyFileManager.writeFile(at: fullPath, base64Content: content) { self.sendResponse(id: id, result: ["status": "ok", "name": name]) } else { self.sendError(id: id, code: -32000, message: "Failed to write file") }
                }
            }
            if let expiry = filePermissionExpiry, expiry > Date() { executeSet() } else { onFileSyncRequested?(name, "Upload", { duration in if let duration = duration { self.filePermissionExpiry = Date().addingTimeInterval(duration) }; executeSet() }, { self.sendError(id: id, code: -1, message: "User denied file write") }) }
        default: sendError(id: id, code: -32601, message: "Method not found")
        }
    }
    
    private func isValidId(_ id: Any?) -> Bool { if let s = id as? String { return !s.isEmpty } else { return id is Int } }
    
    public func sendResponse(id: Any, result: Any) {
        if let idStr = id as? String {
            if idStr.hasPrefix("inv:") {
                let invocationId = String(idStr.dropFirst(4))
                send(json: ["type": "req", "method": "node.invoke.result", "params": ["id": invocationId, "nodeId": self.deviceId, "ok": true, "payload": result]])
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
                send(json: ["type": "req", "method": "node.invoke.result", "params": ["id": invocationId, "nodeId": self.deviceId, "ok": false, "error": ["code": "\(code)", "message": message]]])
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
        socket?.write(string: text)
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
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
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
