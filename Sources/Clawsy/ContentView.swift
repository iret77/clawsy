import SwiftUI
import UserNotifications

struct ContentView: View {
    // Use V2 Manager
    @StateObject private var network = NetworkManagerV2()
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var showingSettings = false
    @State private var showingLog = false
    
    // Persistent Configuration
    @AppStorage("serverHost") private var serverHost = "agenthost"
    @AppStorage("serverPort") private var serverPort = "18789"
    @AppStorage("serverToken") private var serverToken = ""
    @AppStorage("sshUser") private var sshUser = "claw"
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
                        Text("APP_NAME")
                            .font(.system(size: 13, weight: .semibold))
                        
                        Group {
                            if network.connectionStatusKey == "STATUS_CONNECTING" {
                                Text("STATUS_CONNECTING \(network.connectionAttemptCount)")
                            } else {
                                Text(LocalizedStringKey(network.connectionStatusKey))
                            }
                        }
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
                        Label("FULL_SCREEN", systemImage: "rectangle.dashed")
                    }
                    Button(action: {
                        self.isScreenshotInteractive = true
                        self.requestScreenshot()
                    }) {
                        Label("INTERACTIVE_AREA", systemImage: "plus.viewfinder")
                    }
                } label: {
                    MenuItemRow(icon: "camera", title: "SCREENSHOT", isEnabled: network.isConnected, hasChevron: true)
                }
                .menuStyle(.borderlessButton)

                // Clipboard
                Button(action: handleManualClipboardSend) {
                    MenuItemRow(icon: "doc.on.clipboard", title: "PUSH_CLIPBOARD", subtitle: "COPY_TO_AGENT", isEnabled: network.isConnected)
                }
                .buttonStyle(.plain)
                
                // File Sync (USP)
                Button(action: { /* Placeholder for manual sync trigger */ }) {
                    MenuItemRow(icon: "folder.badge.gearshape", title: "FILE_SYNC", subtitle: "MANAGED_FOLDER", isEnabled: network.isConnected)
                }
                .buttonStyle(.plain)
                
                Divider().padding(.vertical, 4).opacity(0.5)
                
                // Connection Control
                Button(action: toggleConnection) {
                    MenuItemRow(
                        icon: network.isConnected ? "power" : "bolt.slash.fill",
                        title: network.isConnected ? "DISCONNECT" : "CONNECT",
                        color: network.isConnected ? .red : .blue
                    )
                }
                .buttonStyle(.plain)

                // Settings
                Button(action: { showingSettings.toggle() }) {
                    MenuItemRow(icon: "gearshape.fill", title: "SETTINGS", isEnabled: true, shortcut: "⌘,")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSettings, arrowEdge: .trailing) {
                    SettingsView(
                        serverHost: $serverHost,
                        serverPort: $serverPort,
                        serverToken: $serverToken,
                        sshUser: $sshUser,
                        isPresented: $showingSettings
                    )
                    .frame(width: 380)
                }
                
                // Debug Log
                Button(action: { showingLog.toggle() }) {
                    MenuItemRow(icon: "terminal.fill", title: "DEBUG_LOG", isEnabled: true)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingLog, arrowEdge: .trailing) {
                    DebugLogView(logText: network.rawLog, isPresented: $showingLog)
                        .frame(width: 400, height: 300)
                }
                
                Divider().padding(.vertical, 4).opacity(0.5)
                
                // Quit
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    MenuItemRow(icon: "xmark.circle.fill", title: "QUIT", isEnabled: true, shortcut: "⌘Q")
                }
                .buttonStyle(.plain)
            }
            .padding(6)
        }
        .frame(width: 240)
        // Background removed to allow NSPopover's native material to show
        .onAppear {
            setupCallbacks()
            // Auto-connect if configured
            if !serverHost.isEmpty && !serverToken.isEmpty {
                network.configure(host: serverHost, port: serverPort, token: serverToken)
                network.connect()
            }
        }
        // Alerts/Popups
        .alert("ALERT_SCREENSHOT_TITLE", isPresented: $showingScreenshotAlert) {
             Button("ALERT_DENY", role: .cancel) {
                 if let rid = pendingRequestId {
                     network.sendError(id: rid, code: -1, message: "User denied screenshot")
                 }
             }
             Button("ALERT_ALLOW", role: .destructive) {
                 takeScreenshot()
             }
         } message: {
             Text("ALERT_SCREENSHOT_BODY")
         }
    }
    
    // --- Actions ---
    
    func getStatusColor() -> Color {
        if network.isConnected { return .green }
        if network.connectionStatusKey.contains("CONNECTING") || network.connectionStatusKey.contains("STARTING") { return .orange }
        return .red
    }
    
    func toggleConnection() {
        if network.isConnected {
            network.disconnect()
        } else {
            network.configure(host: serverHost, port: serverPort, token: serverToken)
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
        
        network.onFileSyncRequested = { filename, operation, onConfirm, onCancel in
            DispatchQueue.main.async {
                appDelegate.showFileSyncRequest(filename: filename, operation: operation, onConfirm: { duration in
                    onConfirm(duration)
                }, onCancel: {
                    onCancel()
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
                Text("DEBUG_LOG_TITLE")
                    .font(.headline)
                Spacer()
                Button("DONE") { isPresented = false }
            }
            
            ScrollView {
                Text(logText.isEmpty ? "NO_DATA" : logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
            .cornerRadius(4)
            
            HStack {
                Text("SELECT_TEXT_COPY")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("COPY_ALL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
            }
        }
        .padding(16)
    }
}

struct SettingsView: View {
    @Binding var serverHost: String
    @Binding var serverPort: String
    @Binding var serverToken: String
    @Binding var sshUser: String
    @Binding var isPresented: Bool
    
    @AppStorage("useSshFallback") private var useSshFallback = true
    @AppStorage("sharedFolderPath") private var sharedFolderPath = "~/Documents/Clawsy"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SETTINGS_TITLE")
                .font(.system(size: 15, weight: .bold))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Gateway Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("GATEWAY", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        HStack {
                            TextField("HOST", text: $serverHost)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            
                            TextField("PORT", text: $serverPort)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 80)
                        }
                        
                        SecureField("TOKEN", text: $serverToken)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // SSH Fallback Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("SSH_FALLBACK", systemImage: "lock.shield")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                            Spacer()
                            Toggle("", isOn: $useSshFallback).toggleStyle(.switch).scaleEffect(0.7)
                        }
                        
                        TextField("SSH_USER", text: $sshUser)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .disabled(!useSshFallback)
                        
                        Text("SSH_FALLBACK_DESC")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    // File Sync Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("SHARED_FOLDER", systemImage: "folder.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                        
                        TextField("PATH", text: $sharedFolderPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        
                        Text("SHARED_FOLDER_DESC")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Divider()
            
            HStack {
                Text("VIBRANT_SECURE")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("DONE") {
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
