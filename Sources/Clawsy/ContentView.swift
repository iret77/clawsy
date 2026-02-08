import SwiftUI

struct ContentView: View {
    @StateObject private var network = NetworkManager()
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var showingSettings = false
    @AppStorage("serverUrl") private var serverUrl = "ws://localhost:8765"
    
    // Alert States
    @State private var showingScreenshotAlert = false
    @State private var isScreenshotInteractive = false
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Header & Status ---
            HStack {
                Text("Clawsy")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Status Pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(network.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(network.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // --- Main Actions List ---
            VStack(spacing: 4) {
                
                // Screenshot Group
                Menu {
                    Button(action: {
                        self.isScreenshotInteractive = false
                        self.requestScreenshot()
                    }) {
                        Label("Full Screen", systemImage: "rectangle.dashed")
                    }
                    Button(action: {
                        self.isScreenshotInteractive = true
                        self.requestScreenshot()
                    }) {
                        Label("Interactive Area", systemImage: "plus.viewfinder")
                    }
                } label: {
                    MenuItemRow(icon: "camera", title: "Screenshot", subtitle: "Capture screen or area")
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
                .disabled(!network.isConnected)

                // Clipboard
                Button(action: handleManualClipboardSend) {
                    MenuItemRow(icon: "doc.on.clipboard", title: "Send Clipboard", subtitle: "Push current clipboard to agent")
                }
                .buttonStyle(.plain)
                .disabled(!network.isConnected)
                
                Divider().padding(.vertical, 4)
                
                // Connection Control
                Button(action: toggleConnection) {
                    MenuItemRow(
                        icon: network.isConnected ? "power" : "bolt.slash.fill",
                        title: network.isConnected ? "Disconnect" : "Connect",
                        color: network.isConnected ? .red : .primary
                    )
                }
                .buttonStyle(.plain)

                // Settings
                Button(action: { showingSettings.toggle() }) {
                    MenuItemRow(icon: "gear", title: "Preferences...")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSettings) {
                    SettingsView(serverUrl: $serverUrl)
                }
                
                Divider().padding(.vertical, 4)
                
                // Quit
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    MenuItemRow(icon: "power", title: "Quit Clawsy", color: .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
        }
        .frame(width: 280) // Standard menu width
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .onAppear {
            setupCallbacks()
            network.connect() // Auto-connect on launch
        }
        // Alerts/Popups
        .alert("Allow Screenshot?", isPresented: $showingScreenshotAlert) {
             Button("Deny", role: .cancel) {
                 network.send(json: ["type": "error", "message": "User denied screenshot"])
             }
             Button("Allow", role: .destructive) {
                 takeScreenshot()
             }
         } message: {
             Text("The agent requested to see your screen.")
         }
    }
    
    // --- Actions ---
    
    func toggleConnection() {
        if network.isConnected {
            network.disconnect()
        } else {
            network.connect()
        }
    }
    
    func requestScreenshot() {
        self.showingScreenshotAlert = true
    }
    
    func takeScreenshot() {
        if let b64 = ScreenshotManager.takeScreenshot(interactive: isScreenshotInteractive) {
            network.send(json: ["type": "screenshot", "data": b64])
        } else {
            network.lastMessage = "Failed to capture screen"
        }
    }
    
    func handleManualClipboardSend() {
        guard let content = ClipboardManager.getClipboardContent() else { return }
        network.send(json: ["type": "clipboard", "data": content])
    }
    
    func setupCallbacks() {
        network.onScreenshotRequested = { interactive in
            self.isScreenshotInteractive = interactive
            self.showingScreenshotAlert = true
            NSApp.activate(ignoringOtherApps: true)
        }
        // Simplified clipboard logic for UI
    }
}

// --- Components ---

struct MenuItemRow: View {
    var icon: String
    var title: String
    var subtitle: String? = nil
    var color: Color = .primary
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(color)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(isHovering ? Color.primary.opacity(0.1) : Color.clear)
        .cornerRadius(5)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hover
            }
        }
    }
}

struct SettingsView: View {
    @Binding var serverUrl: String
    var body: some View {
        Form {
            TextField("Server URL", text: $serverUrl)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Text("Restart required to apply changes.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// Helper for Native Blur
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
