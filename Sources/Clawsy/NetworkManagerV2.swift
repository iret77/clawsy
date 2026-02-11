import Foundation
import Starscream
import CryptoKit
import AppKit

// MARK: - NetworkManagerV2 (Native Node Protocol)

@available(macOS 13.0, *)
class NetworkManagerV2: ObservableObject, WebSocketDelegate {
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    @Published var lastMessage = ""
    
    private var socket: WebSocket?
    private var signingKey: Curve25519.Signing.PrivateKey?
    private var publicKey: Curve25519.Signing.PublicKey?
    
    // Callbacks for UI/Logic
    var onScreenshotRequested: ((Bool, String) -> Void)? // interactive, request_id
    var onClipboardReadRequested: ((String) -> Void)? // request_id
    var onClipboardWriteRequested: ((String, String) -> Void)? // content, request_id
    
    // Gateway Configuration
    // In production, these should come from Settings/UserDefaults
    private var gatewayUrl: URL?
    private var authToken: String?
    
    init() {
        // Load or Generate Identity
        // TODO: Persist keypair in Keychain
        self.signingKey = Curve25519.Signing.PrivateKey()
        self.publicKey = self.signingKey?.publicKey
    }
    
    func configure(url: String, token: String) {
        var processedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Auto-fix URL scheme
        if !processedUrl.contains("://") {
            if processedUrl.contains(".ts.net") || processedUrl.contains("cloud") {
                processedUrl = "wss://" + processedUrl
            } else {
                processedUrl = "ws://" + processedUrl
            }
        }
        
        // Ensure path for WebSocket
        if processedUrl.hasSuffix(".ts.net") {
            processedUrl += "/"
        }
        
        self.gatewayUrl = URL(string: processedUrl)
        self.authToken = token
        print("Configured with URL: \(processedUrl)")
    }

    func connect() {
        guard let url = gatewayUrl, !authToken!.isEmpty else {
            connectionStatus = "Missing Configuration"
            return
        }
        
        connectionStatus = "Connecting..."
        attemptConnection(to: url)
    }
    
    private func attemptConnection(to url: URL) {
        print("Attempting connection to \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }
    
    private func runDiagnostics(error: Error?) {
        let errorDesc = error?.localizedDescription ?? "Unknown error"
        
        if errorDesc.contains("not permitted") || errorDesc.contains("App Transport Security") {
            connectionStatus = "Security Block (Try wss://)"
        } else if errorDesc.contains("refused") {
            connectionStatus = "Server Refused (Check Port)"
        } else if errorDesc.contains("timed out") {
            connectionStatus = "Timeout (Check Network/IP)"
        } else if errorDesc.contains("hostname could not be found") {
            connectionStatus = "DNS Fail (Check URL)"
        } else {
            connectionStatus = "Error: \(errorDesc)"
        }
    }
    
    func disconnect() {
        socket?.disconnect()
    }
    
    // MARK: - WebSocketDelegate
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch event {
            case .connected(let headers):
                self.isConnected = true
                self.connectionStatus = "Connected (Handshaking...)"
                print("websocket is connected: \(headers)")
                
            case .disconnected(let reason, let code):
                self.isConnected = false
                self.connectionStatus = "Disconnected: \(reason)"
                print("websocket is disconnected: \(reason) with code: \(code)")
                
            case .text(let string):
                self.handleMessage(string)
                
            case .binary(let data):
                print("Received data: \(data.count)")
                
            case .ping(_):
                break
            case .pong(_):
                break
            case .viabilityChanged(_):
                break
            case .reconnectSuggested(_):
                break
            case .cancelled:
                self.isConnected = false
                self.connectionStatus = "Cancelled"
            case .error(let error):
                self.isConnected = false
                self.runDiagnostics(error: error)
                print("websocket error: \(error?.localizedDescription ?? "Unknown")")
            case .peerClosed:
                break
            }
        }
    }
    
    // MARK: - Protocol Logic
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // 1. Handle Connect Challenge
        if let event = json["event"] as? String, event == "connect.challenge",
           let payload = json["payload"] as? [String: Any],
           let nonce = payload["nonce"] as? String {
            
            print("Received challenge nonce: \(nonce)")
            performHandshake(nonce: nonce)
            return
        }
        
        // 2. Handle Handshake Response
        if let id = json["id"] as? String, id == "1" {
            if let result = json["result"] as? [String: Any] {
                 print("Handshake Success: \(result)")
                 self.connectionStatus = "Online (Paired)"
            } else if let error = json["error"] as? [String: Any] {
                 print("Handshake Failed: \(error)")
                 self.connectionStatus = "Handshake Failed"
            }
            return
        }
        
        // 3. Handle Requests (node.invoke)
        if let type = json["type"] as? String, type == "req",
           let id = json["id"] as? String,
           let method = json["method"] as? String, method == "node.invoke",
           let params = json["params"] as? [String: Any],
           let command = params["command"] as? String {
            
            handleCommand(id: id, command: command, params: params)
        }
        
        // 4. Handle System Prompts for Approvals (if routed via agent.message/system)
        if let type = json["type"] as? String, type == "req",
           let id = json["id"] as? String,
           let method = json["method"] as? String, method == "clipboard.write.approve",
           let params = json["params"] as? [String: Any],
           let text = params["text"] as? String {
            
            onClipboardWriteRequested?(text, id)
        }
    }
    
    private func performHandshake(nonce: String) {
        guard let signingKey = signingKey, let publicKey = publicKey, let token = authToken else { return }
        
        let tsMs = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Device ID = SHA256(raw_public_key)
        let pubKeyData = publicKey.rawRepresentation
        let deviceId = SHA256.hash(data: pubKeyData).map { String(format: "%02x", $0) }.joined()
        
        // --- CRITICAL Protocol Fix (Matching buildDeviceAuthPayload in device-auth.ts) ---
        // Format: version|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce
        // scopes are joined by ",", but we have none.
        let components = [
            "v2",
            deviceId,
            "openclaw-macos",
            "node",
            "node",
            "", // scopes
            String(tsMs),
            token,
            nonce
        ]
        let payloadString = components.joined(separator: "|")
        // -----------------------------------------------------------------------------
        
        guard let payloadData = payloadString.data(using: .utf8) else { return }
        
        // Sign
        guard let signature = try? signingKey.signature(for: payloadData) else { return }
        
        // Encode Base64URL
        let pubKeyB64 = base64UrlEncode(pubKeyData)
        let sigB64 = base64UrlEncode(signature)
        
        // Construct Connect Request
        let connectReq: [String: Any] = [
            "type": "req",
            "id": "1",
            "method": "connect",
            "params": [
                "minProtocol": 3,
                "maxProtocol": 3,
                "client": [
                    "id": "openclaw-macos",
                    "version": "0.2.0",
                    "platform": "macos",
                    "mode": "node"
                ],
                "role": "node",
                "caps": ["clipboard", "screen", "camera"], // Advertise capabilities
                "commands": ["clipboard.read", "clipboard.write", "screen.capture"],
                "permissions": ["clipboard.read": true, "clipboard.write": true],
                "auth": ["token": token],
                "device": [
                    "id": deviceId,
                    "publicKey": pubKeyB64,
                    "signature": sigB64,
                    "signedAt": tsMs,
                    "nonce": nonce
                ]
            ]
        ]
        
        send(json: connectReq)
    }
    
    private func handleCommand(id: String, command: String, params: [String: Any]) {
        print("Handling command: \(command)")
        
        switch command {
        case "screen.capture":
            // Check params for 'interactive' or 'rect' if supported
            // Default to full screen for now, or respect params if passed
            let interactive = false // TODO: parse from params if needed
            onScreenshotRequested?(interactive, id)
            
        case "clipboard.read":
            onClipboardReadRequested?(id)
            
        case "clipboard.write":
            if let content = params["text"] as? String {
                onClipboardWriteRequested?(content, id)
            } else {
                sendError(id: id, code: -32602, message: "Missing 'text' parameter")
            }
            
        default:
            sendError(id: id, code: -32601, message: "Method not found")
        }
    }
    
    // MARK: - Response Helpers
    
    func sendResponse(id: String, result: Any) {
        let response: [String: Any] = [
            "type": "res",
            "id": id,
            "result": result
        ]
        send(json: response)
    }
    
    func sendError(id: String, code: Int, message: String) {
        let response: [String: Any] = [
            "type": "res",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
        send(json: response)
    }
    
    // MARK: - Manual Events
    
    func sendEvent(kind: String, payload: Any) {
        // Wrap in a standard event structure
        // This assumes the Gateway propagates "node.event" or similar
        let message: [String: Any] = [
            "type": "event",
            "event": "node.event", // Generic node event
            "payload": [
                "kind": kind,
                "data": payload,
                "ts": Int64(Date().timeIntervalSince1970 * 1000)
            ]
        ]
        send(json: message)
    }
    
    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.write(string: text)
    }
    
    // Helper: Base64URL
    private func base64UrlEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
