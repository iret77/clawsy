import SwiftUI
import UserNotifications

struct ContentView: View {
    // Use V2 Manager
    @StateObject private var network = NetworkManagerV2()
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var showingSettings = false
    @State private var showingLog = false
    @State private var showingScreenshotMenu = false
    @State private var showingCameraMenu = false
    
    // Persistent Configuration (UI State only)
    @AppStorage("serverHost") private var serverHost = "agenthost"
    @AppStorage("serverPort") private var serverPort = "18789"
    @AppStorage("serverToken") private var serverToken = ""
    @AppStorage("sshUser") private var sshUser = ""
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
                        Text(LocalizedStringKey("APP_NAME"))
                            .font(.system(size: 13, weight: .semibold))
                        
                        Group {
                            if network.connectionStatus == "STATUS_CONNECTING" {
                                // Dynamic string interpolation for connection attempts
                                Text("STATUS_CONNECTING \(network.connectionAttemptCount)")
                            } else {
                                // Standard localization for static status keys
                                Text(LocalizedStringKey(network.connectionStatus))
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
                Button(action: { showingScreenshotMenu.toggle() }) {
                    MenuItemRow(icon: "camera", title: "SCREENSHOT", isEnabled: network.isConnected, hasChevron: true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showingScreenshotMenu, arrowEdge: .trailing) {
                    VStack(spacing: 0) {
                        Button(action: {
                            showingScreenshotMenu = false
                            self.isScreenshotInteractive = false
                            self.requestScreenshot()
                        }) {
                            MenuItemRow(icon: "rectangle.dashed", title: "FULL_SCREEN", isEnabled: network.isConnected)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            showingScreenshotMenu = false
                            self.isScreenshotInteractive = true
                            self.requestScreenshot()
                        }) {
                            MenuItemRow(icon: "plus.viewfinder", title: "INTERACTIVE_AREA", isEnabled: network.isConnected)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(4)
                    .frame(width: 200)
                }

                // Clipboard
                Button(action: handleManualClipboardSend) {
                    MenuItemRow(icon: "doc.on.clipboard", title: "PUSH_CLIPBOARD", subtitle: "COPY_TO_AGENT", isEnabled: network.isConnected)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                
                // File Sync (USP)
                Button(action: { /* Placeholder for manual sync trigger */ }) {
                    MenuItemRow(icon: "folder.badge.gearshape", title: "FILE_SYNC", subtitle: "MANAGED_FOLDER", isEnabled: network.isConnected)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                // Camera Group
                Button(action: { showingCameraMenu.toggle() }) {
                    MenuItemRow(icon: "video.fill", title: "CAMERA", isEnabled: network.isConnected, hasChevron: true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showingCameraMenu, arrowEdge: .trailing) {
                    VStack(spacing: 0) {
                        Button(action: {
                            showingCameraMenu = false
                            network.sendEvent(kind: "camera.trigger", payload: ["action": "snap"])
                        }) {
                            MenuItemRow(icon: "camera.fill", title: "TAKE_PHOTO", isEnabled: network.isConnected)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            showingCameraMenu = false
                            network.sendEvent(kind: "camera.trigger", payload: ["action": "list"])
                        }) {
                            MenuItemRow(icon: "list.bullet", title: "LIST_CAMERAS", isEnabled: network.isConnected)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(4)
                    .frame(width: 200)
                }
                
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
                .frame(maxWidth: .infinity)

                // Settings
                Button(action: { showingSettings.toggle() }) {
                    MenuItemRow(icon: "gearshape.fill", title: "SETTINGS", isEnabled: true, shortcut: "⌘,")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
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
                .frame(maxWidth: .infinity)
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
                .frame(maxWidth: .infinity)
            }
            .padding(6)
        }
        .frame(width: 240)
        .onAppear {
            setupCallbacks()
            
            // Validate Shared Folder
            if !sharedFolderPath.isEmpty {
                if !ClawsyFileManager.folderExists(at: sharedFolderPath) {
                    let path = sharedFolderPath
                    sharedFolderPath = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let content = UNMutableNotificationContent()
                        content.title = NSLocalizedString("FOLDER_MISSING_TITLE", comment: "")
                        content.body = String(format: NSLocalizedString("FOLDER_MISSING_BODY", comment: ""), path)
                        content.sound = .default
                        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                        UNUserNotificationCenter.current().add(request)
                    }
                }
            }
            
            // Auto-connect if configured
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
        if network.connectionStatus.contains("CONNECTING") || network.connectionStatus.contains("STARTING") { return .orange }
        return .red
    }
    
    func toggleConnection() {
        if network.isConnected {
            network.disconnect()
        } else {
            network.configure(
                host: serverHost, 
                port: serverPort, 
                token: serverToken, 
                sshUser: sshUser, 
                fallback: useSshFallback
            )
            network.connect()
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

        network.onCameraPreviewRequested = { image, onConfirm, onCancel in
            appDelegate.showCameraPreview(image: image, onConfirm: onConfirm, onCancel: onCancel)
        }
    }
}

struct DebugLogView: View {
    var logText: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedStringKey("DEBUG_LOG_TITLE"))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
            
            ScrollView {
                if logText.isEmpty {
                    Text(LocalizedStringKey("NO_DATA"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(logText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
            .cornerRadius(4)
            
            HStack {
                Text(LocalizedStringKey("SELECT_TEXT_COPY"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(LocalizedStringKey("COPY_ALL")) {
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
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("SELECT_SHARED_FOLDER", comment: "")
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                var path = url.path
                let home = NSHomeDirectory()
                if path.hasPrefix(home) {
                    path = path.replacingOccurrences(of: home, with: "~")
                }
                sharedFolderPath = path
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(LocalizedStringKey("SETTINGS_TITLE"))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2) // Positioning slightly higher as requested

            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Gateway Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label(LocalizedStringKey("GATEWAY"), systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        HStack {
                            TextField(LocalizedStringKey("HOST"), text: $serverHost)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            
                            TextField(LocalizedStringKey("PORT"), text: $serverPort)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 80)
                        }
                        
                        SecureField(LocalizedStringKey("TOKEN"), text: $serverToken)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // SSH Fallback Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(LocalizedStringKey("SSH_FALLBACK"), systemImage: "lock.shield")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                            Spacer()
                            Toggle("", isOn: $useSshFallback)
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                                .onChange(of: useSshFallback) { newValue in
                                    // Force sync to UserDefaults
                                    UserDefaults.standard.set(newValue, forKey: "useSshFallback")
                                    UserDefaults.standard.synchronize()
                                }
                        }
                        
                        TextField(LocalizedStringKey("SSH_USER"), text: $sshUser)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .disabled(!useSshFallback)
                        
                        Text(LocalizedStringKey("SSH_FALLBACK_DESC"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    // File Sync Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label(LocalizedStringKey("SHARED_FOLDER"), systemImage: "folder.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                        
                        HStack {
                            TextField(LocalizedStringKey("PATH"), text: $sharedFolderPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            
                            Button(action: selectFolder) {
                                Image(systemName: "folder.fill")
                            }
                        }
                        
                        Text(LocalizedStringKey("SHARED_FOLDER_DESC"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Divider()
            
            HStack {
                Text(LocalizedStringKey("VIBRANT_SECURE"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Auto-saves")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.bottom, 4)
        }
        .padding(20)
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
    }
}
