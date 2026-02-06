import SwiftUI

struct ContentView: View {
    @StateObject private var network = NetworkManager()
    
    // Alert States
    @State private var showingScreenshotAlert = false
    @State private var showingClipboardSendAlert = false
    @State private var showingClipboardReceiveAlert = false
    @State private var pendingClipboardContent = ""
    @State private var showingSettings = false
    @AppStorage("serverUrl") private var serverUrl = "ws://localhost:8765"
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("🦞 Clawsy")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(network.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSettings) {
                    VStack(alignment: .leading) {
                        Text("Settings").font(.headline)
                        TextField("Agent URL", text: $serverUrl)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Text("Restart to apply")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .padding(.top)
            
            Divider()
            
            // Status Area
            VStack(alignment: .leading) {
                Text(network.lastMessage.isEmpty ? "Ready" : network.lastMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Divider()
            
            // Actions
            VStack(spacing: 10) {
                Button(action: {
                    if network.isConnected {
                        network.disconnect()
                    } else {
                        network.connect()
                    }
                }) {
                    Text(network.isConnected ? "Disconnect" : "Connect Agent")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                HStack {
                    // Manual Trigger: Send Screenshot
                    Button(action: {
                        self.showingScreenshotAlert = true
                    }) {
                        Label("Screenshot", systemImage: "camera")
                    }
                    .disabled(!network.isConnected)
                    
                    // Manual Trigger: Send Clipboard
                    Button(action: {
                        self.showingClipboardSendAlert = true
                    }) {
                        Label("Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!network.isConnected)
                }
            }
            
            Spacer()
            
            // Footer
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                
                Spacer()
                Text("v0.1.0")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 300, height: 350)
        .onAppear {
            setupCallbacks()
            // Auto-connect on launch
            network.connect()
        }
        // --- Alerts / Dialogs ---
        
        // 1. Request: Take Screenshot
        .alert("Request: Screenshot", isPresented: $showingScreenshotAlert) {
            Button("Deny", role: .cancel) {
                network.send(json: ["type": "error", "message": "User denied screenshot"])
            }
            Button("Allow", role: .destructive) { // Destructive red to signal caution
                if let b64 = ScreenshotManager.takeScreenshot() {
                    network.send(json: ["type": "screenshot", "data": b64])
                } else {
                    network.lastMessage = "Failed to capture screen"
                }
            }
        } message: {
            Text("CyberClaw is requesting to see your screen. Allow?")
        }
        
        // 2. Request: Read Clipboard
        .alert("Request: Clipboard Access", isPresented: $showingClipboardSendAlert) {
            Button("Deny", role: .cancel) {
                network.send(json: ["type": "error", "message": "User denied clipboard access"])
            }
            Button("Allow", role: .destructive) {
                if let content = ClipboardManager.getClipboardContent() {
                    network.send(json: ["type": "clipboard", "data": content])
                } else {
                    network.lastMessage = "Clipboard empty or not text"
                }
            }
        } message: {
            Text("CyberClaw is requesting to read your clipboard. Allow?")
        }
        
        // 3. Receive: Write to Clipboard
        .alert("Received: Clipboard Content", isPresented: $showingClipboardReceiveAlert) {
            Button("Ignore", role: .cancel) {
                // Do nothing
            }
            Button("Copy", role: .none) {
                ClipboardManager.setClipboardContent(pendingClipboardContent)
                network.send(json: ["type": "ack", "status": "copied"])
            }
        } message: {
            Text("CyberClaw sent text for your clipboard:\n\n\"\(pendingClipboardContent.prefix(50))...\"")
        }
    }
    
    func setupCallbacks() {
        // Wiring Network Events to UI Alerts
        network.onScreenshotRequested = {
            self.showingScreenshotAlert = true
            // Bring app to front so user sees the alert
            NSApp.activate(ignoringOtherApps: true)
        }
        
        network.onClipboardRequested = {
            self.showingClipboardSendAlert = true
            NSApp.activate(ignoringOtherApps: true)
        }
        
        network.onClipboardReceived = { content in
            self.pendingClipboardContent = content
            self.showingClipboardReceiveAlert = true
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
