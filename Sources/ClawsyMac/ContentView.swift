import SwiftUI
import UserNotifications
import ClawsyShared

struct ContentView: View {
    // Use Shared Network Manager
    @StateObject private var network = NetworkManager()
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var showingSettings = false
    @State private var showingLog = false
    @State private var showingScreenshotMenu = false
    @State private var showingCameraMenu = false
    
    // Persistent Configuration (UI State only)
    @AppStorage("serverHost", store: SharedConfig.sharedDefaults) private var serverHost = "agenthost"
    @AppStorage("serverPort", store: SharedConfig.sharedDefaults) private var serverPort = "18789"
    @AppStorage("serverToken", store: SharedConfig.sharedDefaults) private var serverToken = ""
    @AppStorage("sshUser", store: SharedConfig.sharedDefaults) private var sshUser = ""
    @AppStorage("useSshFallback", store: SharedConfig.sharedDefaults) private var useSshFallback = true
    @AppStorage("sharedFolderPath", store: SharedConfig.sharedDefaults) private var sharedFolderPath = "~/Documents/Clawsy"
    
    // Alert States
    @State private var showingScreenshotAlert = false
    @State private var isScreenshotInteractive = false
    @State private var pendingRequestId: Any? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Header & Status ---
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("APP_NAME", bundle: .clawsy)
                        .font(.system(size: 13, weight: .semibold))
                    
                    Group {
                        if network.connectionStatus == "STATUS_CONNECTING" {
                            // Dynamic string interpolation for connection attempts
                            Text("STATUS_CONNECTING \(network.connectionAttemptCount)", bundle: .clawsy)
                        } else {
                            // Standard localization for static status keys
                            Text(LocalizedStringKey(network.connectionStatus), bundle: .clawsy)
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

                // Quick Send
                Button(action: { appDelegate.showQuickSend() }) {
                    MenuItemRow(icon: "paperplane.fill", title: "QUICK_SEND", subtitle: "SEND_AND_FORGET", isEnabled: network.isConnected)
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
                
                Text("v0.2.3 #122")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity)
            }
            .padding(6)
        }
        .frame(width: 240)
        .onAppear {
            appDelegate.networkManager = network // Link for QuickSend
            setupCallbacks()
            
            // Validate Shared Folder
            if !sharedFolderPath.isEmpty {
                if !ClawsyFileManager.folderExists(at: sharedFolderPath) {
                    let path = sharedFolderPath
                    sharedFolderPath = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let content = UNMutableNotificationContent()
                        content.title = NSLocalizedString("FOLDER_MISSING_TITLE", bundle: .clawsy, comment: "")
                        content.body = String(format: NSLocalizedString("FOLDER_MISSING_BODY", bundle: .clawsy, comment: ""), path)
                        content.sound = .default
                        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                        UNUserNotificationCenter.current().add(request)
                    }
                }
            }
            
            // Auto-connect if configured
            if !serverHost.isEmpty && !serverToken.isEmpty {
                network.configure(host: serverHost, port: serverPort, token: serverToken, sshUser: sshUser, fallback: useSshFallback)
                network.connect()
            }
        }
        .onChange(of: network.isHandshakeComplete) { newValue in
            if newValue {
                // Auto-trigger sync event once paired
                network.sendEvent(kind: "file.sync_triggered", payload: ["path": sharedFolderPath])
            }
        }
        // Alerts/Popups
        .alert(Text("ALERT_SCREENSHOT_TITLE", bundle: .clawsy), isPresented: $showingScreenshotAlert) {
             Button(action: {
                 if let rid = pendingRequestId {
                     network.sendError(id: rid, code: -1, message: "User denied screenshot")
                 }
             }) {
                 Text("ALERT_DENY", bundle: .clawsy)
             }
             Button(role: .destructive, action: {
                 takeScreenshot()
             }) {
                 Text("ALERT_ALLOW", bundle: .clawsy)
             }
         } message: {
             Text("ALERT_SCREENSHOT_BODY", bundle: .clawsy)
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
                appDelegate.showStatusHUD(icon: "camera.fill", title: "SCREENSHOT_SENT")
            }
        } else {
            if let rid = pendingRequestId {
                network.sendError(id: rid, code: -1, message: "Screenshot failed")
            }
        }
    }
    
    func handleManualClipboardSend() {
        if let content = ClipboardManager.getClipboardContent() {
            // Use agent.request for clipboard content too
            network.sendEvent(kind: "agent.request", payload: [
                "message": "📋 Clipboard content:\n" + content,
                "sessionKey": "main",
                "deliver": true
            ])
            appDelegate.showStatusHUD(icon: "doc.on.clipboard.fill", title: "CLIPBOARD_SENT")
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("DEBUG_LOG_TITLE", bundle: .clawsy)
                        .font(.system(size: 15, weight: .bold))
                    Text("v0.2.3 #122")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
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
                    Text("NO_DATA", bundle: .clawsy)
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
                Text("SELECT_TEXT_COPY", bundle: .clawsy)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }) {
                    Text("COPY_ALL", bundle: .clawsy)
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
    
    @AppStorage("useSshFallback", store: SharedConfig.sharedDefaults) private var useSshFallback = true
    @AppStorage("sharedFolderPath", store: SharedConfig.sharedDefaults) private var sharedFolderPath = "~/Documents/Clawsy"
    @AppStorage("quickSendHotkey", store: SharedConfig.sharedDefaults) private var quickSendHotkey = "K"
    @AppStorage("pushClipboardHotkey", store: SharedConfig.sharedDefaults) private var pushClipboardHotkey = "V"
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("SELECT_SHARED_FOLDER", bundle: .clawsy, comment: "")
        
        // Finalized flags for unrestricted navigation
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        panel.canDownloadUbiquitousContents = true
        panel.canResolveUbiquitousConflicts = true
        
        DispatchQueue.main.async {
            panel.becomeKey()
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
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("SETTINGS_TITLE", bundle: .clawsy)
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
                VStack(alignment: .leading, spacing: 20) {
                    // Gateway Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label(title: { Text("GATEWAY", bundle: .clawsy) }, icon: { Image(systemName: "antenna.radiowaves.left.and.right") })
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        HStack {
                            TextField(text: $serverHost) {
                                Text("HOST", bundle: .clawsy)
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            
                            TextField(text: $serverPort) {
                                Text("PORT", bundle: .clawsy)
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 80)
                        }
                        
                        SecureField(text: $serverToken) {
                            Text("TOKEN", bundle: .clawsy)
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }
                    
                    // SSH Fallback Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(title: { Text("SSH_FALLBACK", bundle: .clawsy) }, icon: { Image(systemName: "lock.shield") })
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
                        
                        TextField(text: $sshUser) {
                            Text("SSH_USER", bundle: .clawsy)
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(!useSshFallback)
                        
                        Text("SSH_FALLBACK_DESC", bundle: .clawsy)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    // Hotkeys Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label(title: { Text("HOTKEYS", bundle: .clawsy) }, icon: { Image(systemName: "keyboard") })
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.purple)
                        
                        HStack {
                            Text("HOTKEY_QUICK_SEND", bundle: .clawsy)
                                .font(.system(size: 12))
                            Spacer()
                            Text("⌘ + ⇧ +")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            TextField("", text: $quickSendHotkey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 40)
                                .multilineTextAlignment(.center)
                                .onChange(of: quickSendHotkey) { newValue in
                                    if newValue.count > 1 {
                                        quickSendHotkey = String(newValue.prefix(1)).uppercased()
                                    } else {
                                        quickSendHotkey = newValue.uppercased()
                                    }
                                }
                        }
                        
                        HStack {
                            Text("HOTKEY_PUSH_CLIPBOARD", bundle: .clawsy)
                                .font(.system(size: 12))
                            Spacer()
                            Text("⌘ + ⇧ +")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            TextField("", text: $pushClipboardHotkey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 40)
                                .multilineTextAlignment(.center)
                                .onChange(of: pushClipboardHotkey) { newValue in
                                    if newValue.count > 1 {
                                        pushClipboardHotkey = String(newValue.prefix(1)).uppercased()
                                    } else {
                                        pushClipboardHotkey = newValue.uppercased()
                                    }
                                }
                        }
                    }
                    
                    // File Sync Section
                    VStack(alignment: .leading, spacing: 8) {
                        Label(title: { Text("SHARED_FOLDER", bundle: .clawsy) }, icon: { Image(systemName: "folder.badge.plus") })
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                        
                        // Path display
                        Text(sharedFolderPath.isEmpty ? "None" : sharedFolderPath)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 8) {
                            Button(action: selectFolder) {
                                Label(title: { Text("SELECT_FOLDER_BUTTON", bundle: .clawsy) }, icon: { Image(systemName: "folder.fill.badge.plus") })
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            
                            if !sharedFolderPath.isEmpty {
                                Button(action: {
                                    let resolved = sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: resolved)
                                }) {
                                    Label(title: { Text("SHOW_IN_FINDER", bundle: .clawsy) }, icon: { Image(systemName: "magnifyingglass") })
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10) // Prevents focus ring clipping and adds breathing room
                .padding(.vertical, 4)
            }
            
            Divider()
            
            HStack {
                Text("VIBRANT_SECURE", bundle: .clawsy)
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
