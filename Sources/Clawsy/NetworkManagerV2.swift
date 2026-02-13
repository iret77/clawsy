import Foundation
import Starscream
import CryptoKit
import AppKit
import SwiftUI
import os.log

// MARK: - NetworkManagerV2 (Native Node Protocol)

@available(macOS 13.0, *)
class NetworkManagerV2: ObservableObject, WebSocketDelegate {
    private let logger = OSLog(subsystem: "ai.clawsy", category: "Network")
    
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    @Published var lastMessage = ""
    @Published var rawLog = ""
    
    private var socket: WebSocket?
    private var signingKey: Curve25519.Signing.PrivateKey?
    private var publicKey: Curve25519.Signing.PublicKey?
    
    // SSH Tunnel Management
    private var sshProcess: Process?
    private var isUsingSshTunnel = false
    private var connectionAttemptCount = 0
    
    // Callbacks for UI/Logic
    var onScreenshotRequested: ((Bool, String) -> Void)?
    var onClipboardReadRequested: ((String) -> Void)?
    var onClipboardWriteRequested: ((String, String) -> Void)?
    var onFileSyncRequested: ((String, String, @escaping () -> Void, @escaping () -> Void) -> Void)?
    
    // Gateway Configuration
    @AppStorage("serverUrl") private var serverUrl = "wss://agenthost.tailb6e490.ts.net"
    @AppStorage("serverToken") private var serverToken = ""
    @AppStorage("sshHost") private var sshHost = "agenthost"
    @AppStorage("useSshFallback") private var useSshFallback = true
    @AppStorage("sharedFolderPath") private var sharedFolderPath = "~/Documents/Clawsy"
    
    init() {
        self.signingKey = Curve25519.Signing.PrivateKey()
        self.publicKey = self.signingKey?.publicKey
    }
    
    func configure(url: String, token: String) {
        self.serverUrl = url
        self.serverToken = token
        os_log("Configured with URL: %{public}@", log: logger, type: .info, url)
    }

    func connect() {
        guard !serverUrl.isEmpty, !serverToken.isEmpty else {
            connectionStatus = "Missing Configuration"
            return
        }
        
        connectionAttemptCount += 1
        connectionStatus = "Connecting (Attempt \(connectionAttemptCount))..."
        
        let targetUrlStr = isUsingSshTunnel ? "ws://localhost:18789" : serverUrl
        guard let targetUrl = URL(string: targetUrlStr) else {
            connectionStatus = "Invalid URL"
            return
        }
        
        attemptConnection(to: targetUrl)
    }
    
    private func attemptConnection(to url: URL) {
        os_log("Attempting connection to %{public}@", log: logger, type: .info, url.absoluteString)
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }
    
    private func handleConnectionFailure(error: Error?) {
        if useSshFallback && !isUsingSshTunnel && connectionAttemptCount >= 2 {
            startSshTunnel()
        } else {
            runDiagnostics(error: error)
        }
    }
    
    private func startSshTunnel() {
        os_log("Initiating SSH Tunnel Fallback...", log: logger, type: .info)
        connectionStatus = "Starting SSH Tunnel..."
        
        sshProcess?.terminate()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-NT", "-L", "18789:localhost:18789", sshHost]
        
        do {
            try process.run()
            self.sshProcess = process
            self.isUsingSshTunnel = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.connect()
            }
        } catch {
            os_log("Failed to start SSH process: %{public}@", log: logger, type: .error, error.localizedDescription)
            connectionStatus = "SSH Tunnel Failed"
            isUsingSshTunnel = false
        }
    }
    
    private func runDiagnostics(error: Error?) {
        let errorDesc = error?.localizedDescription ?? "Unknown error"
        if errorDesc.contains("refused") {
            connectionStatus = "Offline (Server Refused)"
        } else if errorDesc.contains("timed out") {
            connectionStatus = "Offline (Timeout)"
        } else {
            connectionStatus = "Error: \(errorDesc)"
        }
    }
    
    func disconnect() {
        socket?.disconnect()
        sshProcess?.terminate()
        sshProcess = nil
        isUsingSshTunnel = false
        connectionAttemptCount = 0
    }
    
    // MARK: - WebSocketDelegate
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch event {
            case .connected(_):
                self.isConnected = true
                self.connectionStatus = "Connected (Handshaking...)"
                self.connectionAttemptCount = 0
                os_log("Websocket is connected", log: self.logger, type: .info)
                
            case .disconnected(let reason, let code):
                self.isConnected = false
                self.connectionStatus = "Disconnected"
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
                 self.connectionStatus = "Online (Paired)"
                 if isUsingSshTunnel {
                     self.connectionStatus += " via SSH"
                 }
            } else if json["error"] != nil {
                 self.connectionStatus = "Handshake Failed"
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
                "commands": ["clipboard.read", "clipboard.write", "screen.capture", "file.list", "file.get", "file.set"],
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
            onScreenshotRequested?(params["interactive"] as? Bool ?? false, id)
            
        case "clipboard.read":
            onClipboardReadRequested?(id)
            
        case "clipboard.write":
            if let content = params["text"] as? String {
                onClipboardWriteRequested?(content, id)
            } else {
                sendError(id: id, code: -32602, message: "Missing 'text' parameter")
            }
            
        case "file.list":
            // Clawsy Rule: Only list the shared folder
            let files = ClawsyFileManager.listFiles(at: baseDir)
            let result = files.map { ["name": $0.name, "isDirectory": $0.isDirectory, "size": $0.size, "modified": $0.modified.timeIntervalSince1970] }
            sendResponse(id: id, result: ["files": result, "path": sharedFolderPath])
            
        case "file.get":
            guard let name = params["name"] as? String else {
                sendError(id: id, code: -32602, message: "Missing 'name' parameter")
                return
            }
            let fullPath = (baseDir as NSString).appendingPathComponent(name)
            
            onFileSyncRequested?(name, "Download", {
                if let b64 = ClawsyFileManager.readFile(at: fullPath) {
                    self.sendResponse(id: id, result: ["content": b64, "name": name])
                } else {
                    self.sendError(id: id, code: -32000, message: "Failed to read file")
                }
            }, {
                self.sendError(id: id, code: -1, message: "User denied file access")
            })
            
        case "file.set":
            guard let name = params["name"] as? String, let content = params["content"] as? String else {
                sendError(id: id, code: -32602, message: "Missing 'name' or 'content' parameter")
                return
            }
            let fullPath = (baseDir as NSString).appendingPathComponent(name)
            
            onFileSyncRequested?(name, "Upload", {
                if ClawsyFileManager.writeFile(at: fullPath, base64Content: content) {
                    self.sendResponse(id: id, result: ["status": "ok", "name": name])
                } else {
                    self.sendError(id: id, code: -32000, message: "Failed to write file")
                }
            }, {
                self.sendError(id: id, code: -1, message: "User denied file write")
            })
            
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
        DispatchQueue.main.async { self.rawLog += "\nOUT: \(text)" }
        socket?.write(string: text)
    }
    
    private func base64UrlEncode(_ data: Data) -> String {
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
