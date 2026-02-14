import Foundation
import Starscream
import CryptoKit

// Using Starscream for WebSocket (already in Package.swift)
// Using CryptoKit for Ed25519 (macOS 13+)

@available(macOS 13.0, *)
class HandshakePoC: WebSocketDelegate, ObservableObject {
    var socket: WebSocket?
    var isConnected = false
    
    // Gateway Configuration
    let gatewayUrl = URL(string: "ws://127.0.0.1:18789")!
    let authToken = "e8d547922b7775237f0b3d4cfbd9f44c8aaa9061023e4ef8" // Use from test_handshake.py for now
    
    // Keys
    private var signingKey: Curve25519.Signing.PrivateKey?
    private var publicKey: Curve25519.Signing.PublicKey?
    
    init() {
        // Generate Keys
        self.signingKey = Curve25519.Signing.PrivateKey()
        self.publicKey = self.signingKey?.publicKey
    }
    
    func start() {
        var request = URLRequest(url: gatewayUrl)
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }
    
    func stop() {
        socket?.disconnect()
    }
    
    // MARK: - WebSocketDelegate
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            isConnected = true
            print("websocket is connected: \(headers)")
            
        case .disconnected(let reason, let code):
            isConnected = false
            print("websocket is disconnected: \(reason) with code: \(code)")
            
        case .text(let string):
            handleMessage(string)
            
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
            isConnected = false
        case .error(let error):
            isConnected = false
            print("Error: \(error?.localizedDescription ?? "Unknown")")
        case .peerClosed:
            break
        }
    }
    
    // MARK: - Handshake Logic
    
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
        }
        
        // 2. Handle Handshake Response
        if let id = json["id"] as? String, id == "1",
           let result = json["result"] as? [String: Any] { // Success
             print("Handshake Success: \(result)")
        } else if let id = json["id"] as? String, id == "1",
                  let error = json["error"] as? [String: Any] { // Failure
             print("Handshake Failed: \(error)")
        }
    }
    
    private func performHandshake(nonce: String) {
        guard let signingKey = signingKey, let publicKey = publicKey else { return }
        
        let tsMs = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Device ID = SHA256(raw_public_key)
        let pubKeyData = publicKey.rawRepresentation
        let deviceId = SHA256.hash(data: pubKeyData).map { String(format: "%02x", $0) }.joined()
        
        // Payload String
        // v2|{device_id}|openclaw-macos|node|node||{ts_ms}|{token}|{nonce}
        let payloadString = "v2|\(deviceId)|openclaw-macos|node|node||\(tsMs)|\(authToken)|\(nonce)"
        
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
                "scopes": [],
                "caps": ["clipboard", "screen"],
                "commands": ["clipboard.read", "clipboard.write", "screen.capture"],
                "permissions": ["clipboard.read": true, "clipboard.write": true],
                "auth": ["token": authToken],
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
    
    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.write(string: text)
    }
    
    // Helper: Base64URL (RFC 4648)
    private func base64UrlEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
