import SwiftUI

struct ContentView: View {
    @StateObject private var network = NetworkManager()
    @State private var showingSettings = false
    @AppStorage("serverUrl") private var serverUrl = "ws://localhost:8765"
    
    // Alert States
    @State private var showingScreenshotAlert = false
    @State private var showingClipboardSendAlert = false
    @State private var showingClipboardReceiveAlert = false
    @State private var pendingClipboardContent = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Header ---
            HStack {
                Image("AppIcon") // Will use system icon if available
                    .resizable()
                    .frame(width: 24, height: 24)
                
                Text("Clawsy")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                
                Spacer()
                
                // Settings Button
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSettings) {
                    SettingsView(serverUrl: $serverUrl)
                }
            }
            .padding()
            .background(VisualEffectView(material: .headerView, blendingMode: .behindWindow))
            
            Divider()
            
            // --- Status & Connection ---
            VStack(spacing: 12) {
                HStack {
                    StatusIndicator(isConnected: network.isConnected)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(network.isConnected ? "Connected" : "Disconnected")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(network.isConnected ? .primary : .secondary)
                        
                        Text(network.lastMessage.isEmpty ? "Ready to pair" : network.lastMessage)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    
                    // Connect Toggle
                    Toggle("", isOn: Binding(
                        get: { network.isConnected },
                        set: { _ in
                            if network.isConnected { network.disconnect() }
                            else { network.connect() }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            .padding()
            
            // --- Action Grid ---
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ActionButton(
                    title: "Screenshot",
                    icon: "camera.viewfinder",
                    color: .blue,
                    isEnabled: network.isConnected
                ) {
                    self.showingScreenshotAlert = true
                }
                
                ActionButton(
                    title: "Clipboard",
                    icon: "doc.on.clipboard",
                    color: .orange,
                    isEnabled: network.isConnected
                ) {
                    self.showingClipboardSendAlert = true
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            
            Spacer()
            
            // --- Footer ---
            HStack {
                Text("v0.1.0")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit Clawsy") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 320, height: 380)
        .onAppear {
            setupCallbacks()
            // Auto-connect on launch if URL is set
            network.connect()
        }
        // --- Alerts (Logic remains same, UI improved later) ---
        .alert("Request: Screenshot", isPresented: $showingScreenshotAlert) {
            Button("Deny", role: .cancel) {
                network.send(json: ["type": "error", "message": "User denied screenshot"])
            }
            Button("Allow", role: .destructive) {
                if let b64 = ScreenshotManager.takeScreenshot() {
                    network.send(json: ["type": "screenshot", "data": b64])
                } else {
                    network.lastMessage = "Failed to capture screen"
                }
            }
        } message: {
            Text("CyberClaw is requesting to see your screen. Allow?")
        }
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
        .alert("Received: Clipboard Content", isPresented: $showingClipboardReceiveAlert) {
            Button("Ignore", role: .cancel) {}
            Button("Copy", role: .none) {
                ClipboardManager.setClipboardContent(pendingClipboardContent)
                network.send(json: ["type": "ack", "status": "copied"])
            }
        } message: {
            Text("CyberClaw sent text for your clipboard:\n\n\"\(pendingClipboardContent.prefix(100))...\"")
        }
    }
    
    func setupCallbacks() {
        network.onScreenshotRequested = {
            self.showingScreenshotAlert = true
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

// --- Subviews ---

struct SettingsView: View {
    @Binding var serverUrl: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("ws://100.x.y.z:8765", text: $serverUrl)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
            
            Divider()
            
            Text("Changes apply on reconnect.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct StatusIndicator: View {
    var isConnected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isConnected ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                .frame(width: 32, height: 32)
            
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: isConnected ? Color.green.opacity(0.5) : Color.clear, radius: 4, x: 0, y: 0)
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isEnabled ? color : .secondary)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEnabled ? color.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}

// Helper for Visual Effect Blur (Native macOS look)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}
