import SwiftUI

struct ContentView: View {
    // Use V2 Manager
    @StateObject private var network = NetworkManagerV2()
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var showingSettings = false
    
    // Persistent Configuration
    @AppStorage("serverUrl") private var serverUrl = "ws://localhost:18789"
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
                    SettingsView(serverUrl: $serverUrl, serverToken: $serverToken)
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
        .frame(width: 300) // Slightly wider for status text
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
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
    
    func requestScreenshot() {
        self.showingScreenshotAlert = true
        self.pendingRequestId = nil // Manual trigger has no ID
    }
    
    func takeScreenshot() {
        if let b64 = ScreenshotManager.takeScreenshot(interactive: isScreenshotInteractive) {
            if let rid = pendingRequestId {
                // Respond to Request
                network.sendResponse(id: rid, result: ["format": "png", "base64": b64])
            } else {
                // Manual Send (Event) - TODO: Implement manual event sending in V2
                // For now just log
                print("Manual screenshot taken")
            }
        } else {
            if let rid = pendingRequestId {
                network.sendError(id: rid, code: -1, message: "Screenshot failed")
            }
        }
    }
    
    func handleManualClipboardSend() {
        // TODO: Implement manual send in V2
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
            ClipboardManager.setClipboardContent(content)
            network.sendResponse(id: requestId, result: ["status": "ok"])
        }
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
    @Binding var serverToken: String
    
    var body: some View {
        Form {
            Section(header: Text("Connection")) {
                TextField("Gateway URL", text: $serverUrl)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                
                SecureField("Gateway Token", text: $serverToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            
            Text("Restart required to apply changes.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding()
    }
}

// Helper for Native Blur -> MOVED TO SharedUI.swift
// struct VisualEffectView: NSViewRepresentable { ... }
