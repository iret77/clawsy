import Foundation
import Starscream
import SwiftUI

// --- Configuration ---
// Loaded from UserDefaults
// ---------------------

class NetworkManager: ObservableObject, WebSocketDelegate {
    @Published var isConnected = false
    @Published var lastMessage = ""
    
    private var socket: WebSocket?
    
    // Callbacks for UI/Logic
    var onScreenshotRequested: (() -> Void)?
    var onClipboardRequested: (() -> Void)?
    var onClipboardReceived: ((String) -> Void)?
    
    func connect() {
        let serverUrl = UserDefaults.standard.string(forKey: "serverUrl") ?? "ws://localhost:8765"
        guard let url = URL(string: serverUrl) else { 
            lastMessage = "Invalid URL"
            return 
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }
    
    func disconnect() {
        socket?.disconnect()
    }
    
    func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.write(string: text)
    }
    
    // --- WebSocketDelegate Methods ---
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        DispatchQueue.main.async {
            switch event {
            case .connected(let headers):
                self.isConnected = true
                self.lastMessage = "Connected: \(headers["Server"] ?? "")"
                print("websocket is connected: \(headers)")
                
                // Send Hello
                self.send(json: [
                    "type": "hello",
                    "hostname": Host.current().localizedName ?? "Mac"
                ])
                
            case .disconnected(let reason, let code):
                self.isConnected = false
                self.lastMessage = "Disconnected: \(reason) with code: \(code)"
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
            case .error(let error):
                self.isConnected = false
                self.lastMessage = "Error: \(error?.localizedDescription ?? "Unknown")"
            case .peerClosed:
                break
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = json["command"] as? String else {
            return
        }
        
        print("Received command: \(cmd)")
        
        switch cmd {
        case "screenshot":
            onScreenshotRequested?()
        case "get_clipboard":
            onClipboardRequested?()
        case "set_clipboard":
            if let content = json["content"] as? String {
                onClipboardReceived?(content)
            }
        default:
            print("Unknown command")
        }
    }
}
