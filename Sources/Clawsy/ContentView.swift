import SwiftUI
import UserNotifications

struct ContentView: View {
    // Use V2 Manager
    @StateObject private var network = NetworkManagerV2()
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var showingSettings = false
    @State private var showingLog = false
    
    // Persistent Configuration
    @AppStorage("serverUrl") private var serverUrl = "wss://agenthost.tailb6e490.ts.net"
    @AppStorage("serverToken") private var serverToken = ""
    @AppStorage("sshHost") private var sshHost = "agenthost"
    @AppStorage("useSshFallback") private var useSshFallback = true
    @AppStorage("sharedFolderPath") private var sharedFolderPath = "~/Documents/Clawsy"
    
    // Alert States
    @State private var showingScreenshotAlert = false
    @State private var isScreenshotInteractive = false
    @State private var pendingRequestId: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Header & Status ---
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clawsy")
                        .font(.system(size: 13, weight: .semibold))
                    Text(network.connectionStatus)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status Indicator
                Circle()
                    .fill(getStatusColor())
                    .frame(width: 8, height: 8)
                    .shadow(color: getStatusColor().opacity(0.5), radius: 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            
            Divider().opacity(0.5)
            
            // --- Main Actions List ---
            VStack(spacing: 2) {
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
                    MenuItemRow(icon: "camera", title: "Screenshot", isEnabled: network.isConnected, hasChevron: true)
                }
                .menuStyle(.borderlessButton)

                // Clipboard
                Button(action: handleManualClipboardSend) {
                    MenuItemRow(icon: "doc.on.clipboard", title: "Push Clipboard", subtitle: "Copy to Agent", isEnabled: network.isConnected)
                }
                .buttonStyle(.plain)
                
                // File Sync (USP)
                Button(action: { /* Placeholder for manual sync trigger */ }) {
                    MenuItemRow(icon: "folder.badge.gearshape", title: "File Sync", subtitle: "Managed Folder", isEnabled: network.isConnected)
                }
                .buttonStyle(.plain)
                
                Divider().padding(.vertical, 4).opacity(0.5)
                
                // Connection Control
                Button(action: toggleConnection) {
                    MenuItemRow(
                        icon: network.isConnected ? "power" : "bolt.slash.fill",
                        title: network.isConnected ? "Disconnect" : "Connect",
                        color: network.isConnected ? .red : .blue
                    )
                }
                .buttonStyle(.plain)

                // Settings
                Button(action: { showingSettings.toggle() }) {
                    MenuItemRow(icon: "gearshape.fill", title: "Settings...", isEnabled: true, shortcut: "⌘,")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSettings, arrowEdge: .trailing) {
                    SettingsView(serverUrl: $serverUrl, serverToken: $serverToken, isPresented: $showingSettings)
                        .frame(width: 380)
                }
                
                // Debug Log
                Button(action: { showingLog.toggle() }) {
                    MenuItemRow(icon: "terminal.fill", title: "Debug Log", isEnabled: true)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingLog, arrowEdge: .trailing) {
                    DebugLogView(logText: network.rawLog, isPresented: $showingLog)
                        .frame(width: 400, height: 300)
                }
                
                Divider().padding(.vertical, 4).opacity(0.5)
                
                // Quit
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    MenuItemRow(icon: "xmark.circle.fill", title: "Quit", isEnabled: true, shortcut: "⌘Q")
                }
                .buttonStyle(.plain)
            }
            .padding(6)
        }
        .frame(width: 240)
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
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

struct DebugLogView: View {
    var logText: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Network Debug Log")
                    .font(.headline)
                Spacer()
                Button("Done") { isPresented = false }
            }
            
            ScrollView {
                Text(logText.isEmpty ? "No data received yet." : logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
            .cornerRadius(4)
            
            HStack {
                Text("Select text to copy.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
            }
        }
        .padding(16)
    }
}

struct SettingsView: View {
    @Binding var serverUrl: String
    @Binding var serverToken: String
    @Binding var isPresented: Bool
    
    @AppStorage("sshHost") private var sshHost = "agenthost"
    @AppStorage("useSshFallback") private var useSshFallback = true
    @AppStorage("sharedFolderPath") private var sharedFolderPath = "~/Documents/Clawsy"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 15, weight: .bold))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Gateway Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Gateway", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        TextField("wss://host:port", text: $serverUrl)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        
                        SecureField("Token", text: $serverToken)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // SSH Fallback Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("SSH Fallback", systemImage: "lock.shield")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                            Spacer()
                            Toggle("", isOn: $useSshFallback).toggleStyle(.switch).scaleEffect(0.7)
                        }
                        
                        TextField("SSH Host (e.g. agenthost)", text: $sshHost)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .disabled(!useSshFallback)
                        
                        Text("Auto-tunnels port 18789 if direct connection fails.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    // File Sync Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Shared Folder", systemImage: "folder.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                        
                        TextField("Path", text: $sharedFolderPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        
                        Text("Only files in this folder are visible to the agent.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Divider()
            
            HStack {
                Text("Vibrant & Secure.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(20)
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
    }
}
