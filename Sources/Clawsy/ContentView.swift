import SwiftUI

struct ContentView: View {
    @StateObject private var network = NetworkManager()
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var showingSettings = false
    @AppStorage("serverUrl") private var serverUrl = "ws://localhost:8765"
    
    // Alert States (Screenshot only)
    @State private var showingScreenshotAlert = false
    @State private var isScreenshotInteractive = false
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Header ---
            HStack {
                Image("AppIcon")
                    .resizable()
                    .frame(width: 24, height: 24)
                
                Text("Clawsy")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                
                Spacer()
                
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
            
            // --- Status ---
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
                    
                    // Connect Button (replacing Toggle)
                    Button(action: {
                        if network.isConnected {
                            network.disconnect()
                        } else {
                            network.lastMessage = "Connecting..."
                            network.connect()
                        }
                    }) {
                        Image(systemName: network.isConnected ? "power.circle.fill" : "power.circle")
                            .font(.system(size: 24))
                            .foregroundColor(network.isConnected ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(network.isConnected ? "Disconnect" : "Connect")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor), lineWidth: 1))
            }
            .padding()
            
            // --- Actions ---
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Screenshot Menu
                Menu {
                    Button(action: {
                        self.isScreenshotInteractive = false
                        self.showingScreenshotAlert = true
                    }) {
                        Label("Full Screen", systemImage: "rectangle.dashed")
                    }
                    Button(action: {
                        self.isScreenshotInteractive = true
                        self.showingScreenshotAlert = true
                    }) {
                        Label("Interactive Area", systemImage: "plus.viewfinder")
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 24))
                            .foregroundColor(network.isConnected ? .blue : .secondary)
                        Text("Screenshot")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(network.isConnected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(network.isConnected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!network.isConnected)
                .opacity(network.isConnected ? 1.0 : 0.6)
                
                // Clipboard Button (Manual Send)
                ActionButton(
                    title: "Clipboard",
                    icon: "doc.on.clipboard",
                    color: .orange,
                    isEnabled: network.isConnected
                ) {
                    handleManualClipboardSend()
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            
            Spacer()
            
            // --- Footer ---
            HStack {
                Text("v0.2.0")
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
            network.connect()
        }
        // Screenshot Alert (Simple Yes/No)
        .alert("Request: Screenshot", isPresented: $showingScreenshotAlert) {
            Button("Deny", role: .cancel) {
                network.send(json: ["type": "error", "message": "User denied screenshot"])
            }
            Button("Allow", role: .destructive) {
                if let b64 = ScreenshotManager.takeScreenshot(interactive: isScreenshotInteractive) {
                    network.send(json: ["type": "screenshot", "data": b64])
                } else {
                    network.lastMessage = "Failed to capture screen"
                }
            }
        } message: {
            Text("CyberClaw is requesting to see your screen. Allow?")
        }
    }
    
    // --- Logic ---
    
    func handleManualClipboardSend() {
        guard let content = ClipboardManager.getClipboardContent() else {
            network.lastMessage = "Clipboard empty"
            return
        }
        
        appDelegate.showClipboardRequest(content: content, onConfirm: {
            // Send to Agent
            network.send(json: ["type": "clipboard", "data": content])
        }, onCancel: {
            // Cancelled
        })
    }
    
    func setupCallbacks() {
        network.onScreenshotRequested = { interactive in
            self.isScreenshotInteractive = interactive
            self.showingScreenshotAlert = true
            NSApp.activate(ignoringOtherApps: true)
        }
        
        network.onClipboardRequested = {
            // Read Clipboard -> Show Window
            if let content = ClipboardManager.getClipboardContent() {
                appDelegate.showClipboardRequest(content: content, onConfirm: {
                    network.send(json: ["type": "clipboard", "data": content])
                }, onCancel: {
                    network.send(json: ["type": "error", "message": "User denied clipboard access"])
                })
            } else {
                network.send(json: ["type": "error", "message": "Clipboard empty"])
            }
        }
        
        network.onClipboardReceived = { content in
            // Show Window -> Write Clipboard
            appDelegate.showClipboardRequest(content: content, onConfirm: {
                ClipboardManager.setClipboardContent(content)
                network.send(json: ["type": "ack", "status": "copied"])
            }, onCancel: {
                // Ignore
            })
        }
    }
}

// --- Subviews ---

struct SettingsView: View {
    @Binding var serverUrl: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Settings").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent URL").font(.caption).foregroundColor(.secondary)
                TextField("ws://100.x.y.z:8765", text: $serverUrl)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
            Divider()
            Text("Changes apply on reconnect.").font(.caption2).foregroundColor(.secondary)
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

// ActionButton struct is defined in previous write but to be safe I include it here if I am overwriting the whole file. 
// Wait, I should verify ActionButton is in the file content I read.
// Yes, it was at the end of the read output. I'll include it.

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
                Text(title).font(.caption).fontWeight(.medium).foregroundColor(isEnabled ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isEnabled ? color.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}
