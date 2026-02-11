import SwiftUI
import UserNotifications

struct ContentView: View {
    // Use V2 Manager
    @StateObject private var network = NetworkManagerV2()
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var showingSettings = false
    
    // Persistent Configuration
    @AppStorage("serverUrl") private var serverUrl = "wss://agenthost.tailb6e490.ts.net"
    @AppStorage("serverToken") private var serverToken = ""
    
    // Alert States
    @State private var showingScreenshotAlert = false
    @State private var isScreenshotInteractive = false
    @State private var pendingRequestId: String? = nil
    
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
                        .fill(getStatusColor())
                        .frame(width: 8, height: 8)
                    Text(network.connectionStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
            VStack(spacing: 6) {
                
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
                    MenuItemRow(icon: "camera", title: "Screenshot", subtitle: "Capture screen or area", isEnabled: network.isConnected)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)

                // Clipboard
                Button(action: handleManualClipboardSend) {
                    MenuItemRow(icon: "doc.on.clipboard", title: "Send Clipboard", subtitle: "Push current clipboard to agent", isEnabled: network.isConnected)
                }
                .buttonStyle(.plain)
                
                Divider().padding(.vertical, 4)
                
                // Connection Control
                Button(action: toggleConnection) {
                    MenuItemRow(
                        icon: network.isConnected ? "power" : "bolt.slash.fill",
                        title: network.isConnected ? "Disconnect" : "Connect",
                        color: network.isConnected ? .red : .blue,
                        isEnabled: true
                    )
                }
                .buttonStyle(.plain)

                // Settings
                Button(action: { showingSettings.toggle() }) {
                    MenuItemRow(icon: "gearshape.fill", title: "Preferences...", isEnabled: true)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSettings, arrowEdge: .trailing) {
                    SettingsView(serverUrl: $serverUrl, serverToken: $serverToken, isPresented: $showingSettings)
                        .frame(width: 380)
                }
                
                Divider().padding(.vertical, 4)
                
                // Surprise Button (Project X)
                Button(action: triggerSurprise) {
                    MenuItemRow(icon: "sparkles", title: "Lobster Mode", subtitle: "Execute Fire Sequence", color: .orange, isEnabled: true)
                }
                .buttonStyle(.plain)

                Divider().padding(.vertical, 4)
                
                // Quit
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    MenuItemRow(icon: "xmark.circle.fill", title: "Quit Clawsy", color: .secondary, isEnabled: true)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            setupCallbacks()
            // Auto-connect if configured
            if !serverUrl.isEmpty && !serverToken.isEmpty {
                network.configure(url: serverUrl, token: serverToken)
                network.connect()
            }
        }
        // Alerts/Popups
        .alert("Allow Screenshot?", isPresented: $showingScreenshotAlert) {
             Button("Deny", role: .cancel) {
                 if let rid = pendingRequestId {
                     network.sendError(id: rid, code: -1, message: "User denied screenshot")
                 }
             }
             Button("Allow", role: .destructive) {
                 takeScreenshot()
             }
         } message: {
             Text("The agent requested to see your screen.")
         }
    }
    
    // --- Actions ---
    
    func getStatusColor() -> Color {
        if network.isConnected { return .green }
        if network.connectionStatus.contains("Connecting") { return .orange }
        return .red
    }
    
    func toggleConnection() {
        if network.isConnected {
            network.disconnect()
        } else {
            network.configure(url: serverUrl, token: serverToken)
            network.connect()
        }
    }
    
    func triggerSurprise() {
        let content = UNMutableNotificationContent()
        content.title = "🦞 LOBSTER MODE ACTIVATED!"
        content.body = "Fire Sequence initiated. CyberClaw is watching. 2035 is now."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        
        if network.isConnected {
            network.sendEvent(kind: "surprise", payload: ["msg": "Lobster Mode Triggered"])
        }
    }
    
    func requestScreenshot() {
        self.showingScreenshotAlert = true
        self.pendingRequestId = nil
    }
    
    func takeScreenshot() {
        if let b64 = ScreenshotManager.takeScreenshot(interactive: isScreenshotInteractive) {
            if let rid = pendingRequestId {
                network.sendResponse(id: rid, result: ["format": "png", "base64": b64])
            } else {
                network.sendEvent(kind: "screenshot", payload: ["format": "png", "base64": b64])
            }
        } else {
            if let rid = pendingRequestId {
                network.sendError(id: rid, code: -1, message: "Screenshot failed")
            }
        }
    }
    
    func handleManualClipboardSend() {
        if let content = ClipboardManager.getClipboardContent() {
            network.sendEvent(kind: "clipboard", payload: ["text": content])
        }
    }
    
    func setupCallbacks() {
        network.onScreenshotRequested = { interactive, requestId in
            self.isScreenshotInteractive = interactive
            self.pendingRequestId = requestId
            self.showingScreenshotAlert = true
            NSApp.activate(ignoringOtherApps: true)
        }
        
        network.onClipboardReadRequested = { requestId in
            if let content = ClipboardManager.getClipboardContent() {
                network.sendResponse(id: requestId, result: ["text": content])
            } else {
                network.sendError(id: requestId, code: -1, message: "Clipboard empty or unavailable")
            }
        }
        
        network.onClipboardWriteRequested = { content, requestId in
            DispatchQueue.main.async {
                appDelegate.showClipboardRequest(content: content, onConfirm: {
                    ClipboardManager.setClipboardContent(content)
                    network.sendResponse(id: requestId, result: ["status": "ok"])
                }, onCancel: {
                    network.sendError(id: requestId, code: -1, message: "User denied clipboard write")
                })
            }
        }
    }
}

// --- Components ---

struct MenuItemRow: View {
    var icon: String
    var title: String
    var subtitle: String? = nil
    var color: Color = .primary
    var isEnabled: Bool = true
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isEnabled ? color : color.opacity(0.3))
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isEnabled ? .primary : .primary.opacity(0.4))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(isEnabled ? .secondary : .secondary.opacity(0.3))
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isHovering && isEnabled ? Color.primary.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .onHover { hover in
            if isEnabled {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovering = hover
                }
            }
        }
    }
}

struct SettingsView: View {
    @Binding var serverUrl: String
    @Binding var serverToken: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Gateway URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("wss://your-agent.ts.net", text: $serverUrl)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                
                Text("Gateway Token")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("Enter token...", text: $serverToken)
                    .textFieldStyle(.roundedBorder)
            }
            
            Divider()
            
            HStack {
                Text("Changes apply after reconnect.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
    }
}
