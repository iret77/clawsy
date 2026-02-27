import SwiftUI
import UserNotifications
import ClawsyShared

struct ContentView: View {
    // Use Shared Network Manager
    @StateObject private var network = NetworkManager()
    @StateObject private var taskStore = TaskStore()
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var showingSettings = false
    @State private var showingLog = false
    @State private var showingMetadata = false
    @State private var showingMissionControl = false
    @State private var ruleEditorFolderPath: String? = nil
    @State private var showingScreenshotMenu = false
    @State private var showingCameraMenu = false
    @State private var isScreenshotInteractive = false
    @State private var showingOnboarding = false
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    
    // Persistent Configuration (UI State only)
    @AppStorage("serverHost", store: SharedConfig.sharedDefaults) private var serverHost = "agenthost"
    @AppStorage("serverPort", store: SharedConfig.sharedDefaults) private var serverPort = "18789"
    @AppStorage("serverToken", store: SharedConfig.sharedDefaults) private var serverToken = ""
    @AppStorage("sshUser", store: SharedConfig.sharedDefaults) private var sshUser = ""
    @AppStorage("useSshFallback", store: SharedConfig.sharedDefaults) private var useSshFallback = true
    @AppStorage("sharedFolderPath", store: SharedConfig.sharedDefaults) private var sharedFolderPath = "~/Documents/Clawsy"
    @AppStorage("extendedContextEnabled", store: SharedConfig.sharedDefaults) private var extendedContextEnabled = false
    
    @State private var fileWatcher: FileWatcher?
    @State private var agentModel: String? = nil
    @State private var agentName: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Header & Status ---
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("APP_NAME", bundle: .clawsy)
                        .font(.system(size: 13, weight: .semibold))
                    
                    Group {
                        if network.connectionStatus == "STATUS_CONNECTING" {
                            Text("STATUS_CONNECTING \(network.connectionAttemptCount)", bundle: .clawsy)
                        } else {
                            Text(LocalizedStringKey(network.connectionStatus), bundle: .clawsy)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                    if let model = agentModel {
                        HStack(spacing: 3) {
                            Image(systemName: "brain")
                                .font(.system(size: 9))
                            Text(model)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary.opacity(0.8))
                    }
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
                            self.takeScreenshotAndSend(interactive: false)
                        }) {
                            MenuItemRow(icon: "rectangle.dashed", title: "FULL_SCREEN", isEnabled: network.isConnected)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            showingScreenshotMenu = false
                            self.takeScreenshotAndSend(interactive: true)
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
                            self.takePhotoAndSend()
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

                // Last Metadata
                Button(action: { showingMetadata.toggle() }) {
                    MenuItemRow(icon: "info.bubble.fill", title: "LAST_METADATA", isEnabled: true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showingMetadata, arrowEdge: .trailing) {
                    MetadataView(network: network, isPresented: $showingMetadata)
                        .frame(width: 350, height: 320)
                }
                
                // Mission Control (Task Overview)
                Button(action: { showingMissionControl.toggle() }) {
                    ZStack(alignment: .trailing) {
                        MenuItemRow(icon: "list.bullet.clipboard", title: "MISSION_CONTROL_TITLE", isEnabled: true)
                        if !taskStore.tasks.isEmpty {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showingMissionControl, arrowEdge: .trailing) {
                    MissionControlView(taskStore: taskStore)
                }

                // Setup / Onboarding
                Button(action: { appDelegate.openOnboardingWindow(onboardingCompleted: $onboardingCompleted) }) {
                    MenuItemRow(icon: "checklist", title: "SETUP", isEnabled: true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

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
            
            // Wire up task updates (primary: .agent_status.json in Shared Folder via FileWatcher)
            network.onTaskUpdate = { agent, title, progress, status in
                taskStore.updateTask(agentName: agent, title: title, progress: progress, statusText: status)
            }

            // Auto-provision .clawsy files in shared folder
            if !sharedFolderPath.isEmpty {
                let resolved = sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
                DispatchQueue.global(qos: .background).async {
                    ClawsyManifestManager.provisionAll(in: resolved)
                }
            }

            // Listen for FinderSync actions via Darwin notification
            ActionBridge.observe {
                if let action = ActionBridge.consumeAction() {
                    handleFinderSyncAction(action)
                }
            }
            

            
            // Auto-connect if configured
            if !serverHost.isEmpty && !serverToken.isEmpty {
                network.configure(host: serverHost, port: serverPort, token: serverToken, sshUser: sshUser, fallback: useSshFallback)
                network.connect()
            }
            
            setupFileWatcher()
        }
        .onChange(of: sharedFolderPath) { _ in
            setupFileWatcher()
        }
        .onChange(of: network.isHandshakeComplete) { newValue in
            if newValue {
                // Auto-trigger sync event once paired
                network.sendEvent(kind: "file.sync_triggered", payload: ["path": sharedFolderPath])
            }
        }
        .onChange(of: network.isConnected) { connected in
            if !connected {
                // Connection lost — clear stale tasks immediately
                taskStore.clearAll()
            }
        }
        .sheet(isPresented: Binding(
            get: { ruleEditorFolderPath != nil },
            set: { if !$0 { ruleEditorFolderPath = nil } }
        )) {
            if let folderPath = ruleEditorFolderPath {
                RuleEditorView(folderPath: folderPath, isPresented: Binding(
                    get: { ruleEditorFolderPath != nil },
                    set: { if !$0 { ruleEditorFolderPath = nil } }
                ))
            }
        }

    }
    
    // --- Actions ---
    
    func handleFinderSyncAction(_ action: PendingAction) {
        switch action.kind {
        case "open_rule_editor":
            ruleEditorFolderPath = action.folderPath
        case "send_telemetry":
            if network.isConnected {
                if let jsonString = ClawsyEnvelopeBuilder.build(type: "telemetry", content: "📡 Telemetrie von \(action.folderPath)", includeTelemetry: true) {
                    network.sendServiceEvent(message: jsonString)
                }
            }
        case "run_actions":
            guard network.isConnected else { break }
            let folderURL = URL(fileURLWithPath: action.folderPath)
            let files = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
            for fileURL in files {
                let fileName = fileURL.lastPathComponent
                guard !fileName.hasPrefix(".") else { continue }
                let rules = ClawsyManifestManager.matchingRules(for: fileName, in: action.folderPath, trigger: "manual")
                let resolvedPath = sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
                for rule in rules {
                    let relativePath = fileURL.path.replacingOccurrences(of: resolvedPath, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    switch rule.action {
                    case "send_to_agent":
                        let message = rule.prompt.isEmpty ? "📂 \(relativePath)" : "\(rule.prompt)\n\nDatei: \(relativePath)"
                        network.sendServiceEvent(message: message, payload: ["trigger": "manual", "fileName": fileName, "relativePath": relativePath, "ruleId": rule.id])
                    case "notify":
                        let content = UNMutableNotificationContent()
                        content.title = NSLocalizedString("RULE_NOTIFY_TITLE", bundle: .clawsy, comment: "")
                        content.body = rule.prompt.isEmpty ? fileName : "\(rule.prompt): \(fileName)"
                        content.sound = .default
                        let req = UNNotificationRequest(identifier: "manual-\(rule.id)-\(UUID().uuidString.prefix(8))", content: content, trigger: nil)
                        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
                    default: break
                    }
                }
            }
        default:
            break
        }
    }

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
    
    // Manual screenshot trigger
    func takeScreenshotAndSend(interactive: Bool) {
        if let b64 = ScreenshotManager.takeScreenshot(interactive: interactive) {
            network.sendScreenshot(base64: b64, mimeType: "image/jpeg")
            appDelegate.showStatusHUD(icon: "camera.fill", title: "SCREENSHOT_SENT")
        }
    }
    
    // Manual camera trigger
    func takePhotoAndSend() {
        CameraManager.takePhoto(deviceId: nil) { b64 in
            if let b64 = b64 {
                network.sendScreenshot(base64: b64, mimeType: "image/jpeg")
                DispatchQueue.main.async {
                    appDelegate.showStatusHUD(icon: "camera.fill", title: "PHOTO_SENT")
                }
            } else {
                DispatchQueue.main.async {
                    appDelegate.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "CAPTURE_FAILED")
                }
            }
        }
    }
    
    func handleManualClipboardSend() {
        if let content = ClipboardManager.getClipboardContent() {
            var envelopeData: [String: Any] = [
                "version": SharedConfig.versionDisplay,
                "type": "clipboard",
                "localTime": ISO8601DateFormatter().string(from: Date()),
                "tz": TimeZone.current.identifier,
                "content": content
            ]
            
            if SharedConfig.extendedContextEnabled {
                envelopeData["telemetry"] = NetworkManager.getTelemetry()
            }

            let envelope: [String: Any] = ["clawsy_envelope": envelopeData]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: envelope),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                // Full clipboard data → clawsy-service (silent background context)
                network.sendServiceEvent(message: jsonString)

                // Brief hint → main session (so agent is immediately aware)
                let preview: String
                if let text = content["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let short = trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
                    preview = "📋 Clipboard: \"\(short)\" (\(trimmed.count) Zeichen)"
                } else if let _ = content["image"] {
                    preview = "📋 Clipboard: [Bild]"
                } else {
                    preview = "📋 Clipboard synchronisiert"
                }
                let hint: [String: Any] = ["clawsy_envelope": ["type": "clipboard_hint", "preview": preview]]
                if let hintData = try? JSONSerialization.data(withJSONObject: hint),
                   let hintString = String(data: hintData, encoding: .utf8) {
                    network.sendDeeplink(message: hintString, sessionKey: "main")
                }

                appDelegate.showStatusHUD(icon: "doc.on.clipboard.fill", title: "CLIPBOARD_SENT")
            }
        }
    }
    
    func setupFileWatcher() {
        fileWatcher?.stop()
        let resolvedPath = sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        guard !sharedFolderPath.isEmpty, ClawsyFileManager.folderExists(at: resolvedPath) else { return }
        
        let watcher = FileWatcher(url: URL(fileURLWithPath: resolvedPath))
        watcher.callback = { changedPath in
            // Check if this is the agent status file
            if changedPath.hasSuffix(".agent_status.json") {
                let fileURL = URL(fileURLWithPath: changedPath)
                taskStore.loadFromFile(fileURL)
                return
            }

            // Check if this is the agent info file (model/session info)
            if changedPath.hasSuffix(".agent_info.json") {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: changedPath)),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async {
                        agentModel = json["model"] as? String
                        agentName = json["agentName"] as? String
                    }
                }
                return
            }

            // Extract relative path for the agent
            let relativePath = changedPath.replacingOccurrences(of: resolvedPath, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            // --- .clawsy Rule Matching ---
            let changedURL = URL(fileURLWithPath: changedPath)
            let fileName = changedURL.lastPathComponent
            let parentFolder = changedURL.deletingLastPathComponent().path

            // Skip hidden files and .clawsy manifests themselves
            if !fileName.hasPrefix(".") {
                let matchedRules = ClawsyManifestManager.matchingRules(for: fileName, in: parentFolder, trigger: "file_added")
                for rule in matchedRules {
                    switch rule.action {
                    case "send_to_agent":
                        let message = rule.prompt.isEmpty
                            ? "📂 Neue Datei: \(relativePath)"
                            : "\(rule.prompt)\n\nDatei: \(relativePath)"
                        network.sendServiceEvent(message: message, payload: [
                            "trigger": "file_added",
                            "fileName": fileName,
                            "relativePath": relativePath,
                            "ruleId": rule.id
                        ])
                    case "notify":
                        DispatchQueue.main.async {
                            let content = UNMutableNotificationContent()
                            content.title = NSLocalizedString("RULE_NOTIFY_TITLE", bundle: .clawsy, comment: "")
                            content.body = rule.prompt.isEmpty ? fileName : "\(rule.prompt): \(fileName)"
                            content.sound = .default
                            let req = UNNotificationRequest(identifier: "rule-\(rule.id)-\(UUID().uuidString.prefix(8))", content: content, trigger: nil)
                            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
                        }
                    default:
                        break
                    }
                }
            }

            // Debounce/Throttle could be added here, but for now we send the event
            network.sendEvent(kind: "file.sync_triggered", payload: [
                "path": sharedFolderPath,
                "changedPath": relativePath
            ])
        }
        watcher.start()
        self.fileWatcher = watcher
    }
    
    func setupCallbacks() {
        network.onScreenshotRequested = { interactive, requestId in
            DispatchQueue.main.async {
                appDelegate.showScreenshotRequest(
                    requestedInteractive: interactive,
                    onConfirm: { userInteractive in
                        if let b64 = ScreenshotManager.takeScreenshot(interactive: userInteractive) {
                            network.sendResponse(id: requestId, result: ["format": "jpeg", "base64": b64])
                        } else {
                            network.sendError(id: requestId, code: -1, message: "Screenshot failed")
                        }
                    },
                    onCancel: {
                        network.sendError(id: requestId, code: -1, message: "User denied screenshot")
                    }
                )
            }
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

// ... DebugLogView, MetadataView, SettingsView remain unchanged (they are simple Views) ...
// We need to include them in the file content or they will be lost if we overwrite.
// Since the file is large and we want to be safe, I will include the full content.
// WAIT: The previous read returned the FULL content. I will reuse the bottom part.

struct DebugLogView: View {
    var logText: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DEBUG_LOG_TITLE", bundle: .clawsy)
                        .font(.system(size: 15, weight: .bold))
                    Text(SharedConfig.versionDisplay)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider().opacity(0.3)
            
            // Log Content
            ScrollView {
                if logText.isEmpty {
                    Text("NO_DATA", bundle: .clawsy)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                } else {
                    Text(logText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
            .background(Color.black.opacity(0.05))
            
            Divider().opacity(0.3)
            
            // Footer
            HStack {
                Text("SELECT_TEXT_COPY", bundle: .clawsy)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }) {
                    Text("COPY_ALL", bundle: .clawsy)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.02))
        }
    }
}

struct MetadataView: View {
    @ObservedObject var network: NetworkManager
    @Binding var isPresented: Bool
    
    func moodString(for score: Double) -> String {
        if score < 30 { return "Stressed 😫" }
        if score < 60 { return "Busy 😰" }
        if score < 85 { return "Focused 👨‍💻" }
        return "Flow 🌊"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Label(title: { Text("LAST_METADATA", bundle: .clawsy) }, icon: { Image(systemName: "info.circle.fill") })
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider().opacity(0.3)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MetadataRow(label: "Version", value: SharedConfig.versionDisplay)
                    MetadataRow(label: "Server Status", value: network.isServerClawsyAware ? "Ready (\(network.serverVersion))" : "Basic")
                    MetadataRow(label: "Local Time", value: ISO8601DateFormatter().string(from: Date()))
                    MetadataRow(label: "Timezone", value: TimeZone.current.identifier)
                    
                    if SharedConfig.extendedContextEnabled {
                        Divider().padding(.vertical, 4).opacity(0.3)
                        Text("EXTENDED_CONTEXT", bundle: .clawsy)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)
                        
                        let telemetry = NetworkManager.getTelemetry()
                        MetadataRow(label: "Device", value: telemetry["deviceName"] as? String ?? "Unknown")
                        
                        if let battery = telemetry["batteryLevel"] as? Float, battery >= 0 {
                            MetadataRow(label: "Battery", value: "\(Int(battery * 100))%\(telemetry["isCharging"] as? Bool == true ? " ⚡️" : "")")
                        }
                        
                        if let app = telemetry["activeApp"] as? String {
                            MetadataRow(label: "Active App", value: app)
                        }
                        
                        if let thermal = telemetry["thermalState"] as? Int {
                            let states = ["Normal", "Fair", "Serious", "Critical"]
                            if thermal < states.count {
                                MetadataRow(label: "Thermal", value: states[thermal])
                            }
                        }

                        if let mood = telemetry["moodScore"] as? Double {
                            MetadataRow(label: "User Mood", value: moodString(for: mood))
                        }
                    } else {
                        Text("EXTENDED_CONTEXT_DISABLED", bundle: .clawsy)
                            .font(.system(size: 10).italic())
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(Color.black.opacity(0.05))
            
            Divider().opacity(0.3)
            
            // Footer
            HStack {
                Text("METADATA_VIEW_DESC", bundle: .clawsy)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.02))
        }
    }
}

struct MetadataRow: View {
    var label: String
    var value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
        }
    }
}

struct SettingsView: View {
    @Binding var serverHost: String
    @Binding var serverPort: String
    @Binding var serverToken: String
    @Binding var sshUser: String
    @AppStorage("extendedContextEnabled", store: SharedConfig.sharedDefaults) private var extendedContextEnabled = false
    @Binding var isPresented: Bool
    
    @ObservedObject var updateManager = UpdateManager.shared
    
    @AppStorage("useSshFallback", store: SharedConfig.sharedDefaults) private var useSshFallback = true
    @AppStorage("sharedFolderPath", store: SharedConfig.sharedDefaults) private var sharedFolderPath = "~/Documents/Clawsy"
    @AppStorage("quickSendHotkey", store: SharedConfig.sharedDefaults) private var quickSendHotkey = "K"
    @AppStorage("pushClipboardHotkey", store: SharedConfig.sharedDefaults) private var pushClipboardHotkey = "V"
    
    func selectFolder() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = NSLocalizedString("SELECT_SHARED_FOLDER", bundle: .clawsy, comment: "")
            panel.resolvesAliases = true
            
            // Fix: Start at current folder or Home
            if !sharedFolderPath.isEmpty {
                let resolved = sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
                panel.directoryURL = URL(fileURLWithPath: resolved)
            } else {
                panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
            }

            NSApp.activate(ignoringOtherApps: true)
            
            panel.begin { response in
                if response == .OK {
                    guard let url = panel.url else { return }
                    
                    var path = url.path
                    let home = NSHomeDirectory()
                    if path.hasPrefix(home) {
                        path = path.replacingOccurrences(of: home, with: "~")
                    }
                    
                    do {
                        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                        
                        // Stop old access if any
                        SharedConfig.resolvedFolderUrl?.stopAccessingSecurityScopedResource()
                        
                        // Start new access
                        if url.startAccessingSecurityScopedResource() {
                            SharedConfig.resolvedFolderUrl = url
                        }
                        
                        DispatchQueue.main.async {
                            SharedConfig.sharedFolderBookmark = data
                            self.sharedFolderPath = path
                        }
                    } catch {
                        print("Failed to create bookmark: \(error)")
                    }
                }
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Text("SETTINGS_TITLE", bundle: .clawsy)
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().opacity(0.3)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Gateway Section
                    VStack(alignment: .leading, spacing: 10) {
                        Label(title: { Text("GATEWAY", bundle: .clawsy) }, icon: { Image(systemName: "antenna.radiowaves.left.and.right") })
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        HStack(spacing: 8) {
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
                    
                    Divider().opacity(0.3)
                    
                    // SSH Fallback Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(title: { Text("SSH_FALLBACK", bundle: .clawsy) }, icon: { Image(systemName: "lock.shield") })
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                            Spacer()
                            Toggle("", isOn: $useSshFallback)
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                        }
                        
                        TextField(text: $sshUser) {
                            Text("SSH_USER", bundle: .clawsy)
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(!useSshFallback)
                        .opacity(useSshFallback ? 1.0 : 0.5)

                        HStack(spacing: 10) {
                            Button { selectSshKey() } label: {
                                Label(NSLocalizedString("IMPORT_SSH_KEY", bundle: .clawsy, comment: ""), systemImage: "key.fill")
                            }
                            .disabled(!useSshFallback)

                            Button { removeSshKey() } label: {
                                Label(NSLocalizedString("REMOVE_SSH_KEY", bundle: .clawsy, comment: ""), systemImage: "trash")
                            }
                            .disabled(!useSshFallback || !sshKeyInstalled)

                            Spacer()

                            Text(NSLocalizedString(sshKeyInstalled ? "KEY_INSTALLED" : "KEY_NOT_SET", bundle: .clawsy, comment: ""))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .opacity(useSshFallback ? 1.0 : 0.5)

                        Text("SSH_FALLBACK_DESC", bundle: .clawsy)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider().opacity(0.3)

                    // Extended Context Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(title: { Text("EXTENDED_CONTEXT", bundle: .clawsy) }, icon: { Image(systemName: "chart.bar.doc.horizontal") })
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.cyan)
                            
                            Button(action: {}) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help(NSLocalizedString("EXTENDED_CONTEXT_HELP", bundle: .clawsy, comment: ""))

                            Spacer()
                            Toggle("", isOn: $extendedContextEnabled)
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                        }
                        
                        Text("EXTENDED_CONTEXT_DESC", bundle: .clawsy)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Hotkeys Section
                    VStack(alignment: .leading, spacing: 12) {
                        Label(title: { Text("HOTKEYS", bundle: .clawsy) }, icon: { Image(systemName: "keyboard") })
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.purple)
                        
                        HStack {
                            Text("HOTKEY_QUICK_SEND", bundle: .clawsy)
                                .font(.system(size: 12))
                            Spacer()
                            Text("⌘ + ⇧ +")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            TextField("", text: $quickSendHotkey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced, weight: .bold))
                                .frame(width: 44)
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
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            TextField("", text: $pushClipboardHotkey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced, weight: .bold))
                                .frame(width: 44)
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
                    
                    Divider().opacity(0.3)
                    
                    // Updates Section
                    VStack(alignment: .leading, spacing: 10) {
                        Label(title: { Text("UPDATES", bundle: .clawsy) }, icon: { Image(systemName: "arrow.triangle.2.circlepath") })
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        HStack {
                            Text(String(format: NSLocalizedString("CURRENT_VERSION %@", bundle: .clawsy, comment: ""), SharedConfig.versionDisplay))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if updateManager.isChecking {
                                ProgressView()
                                    .scaleEffect(0.5)
                            } else if updateManager.isInstalling {
                                HStack(spacing: 6) {
                                    ProgressView(value: updateManager.downloadProgress)
                                        .frame(width: 80)
                                    Text("\(Int(updateManager.downloadProgress * 100))%")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            } else if updateManager.updateAvailable {
                                Button(String(format: NSLocalizedString("INSTALL_VERSION %@", bundle: .clawsy, comment: ""), updateManager.updateVersion)) {
                                    updateManager.downloadAndInstall()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .lineLimit(1)
                                .fixedSize()
                            } else {
                                Button(action: { updateManager.checkForUpdates(silent: false) }) {
                                    Label(title: { Text("CHECK_NOW", bundle: .clawsy) }, icon: { Image(systemName: "arrow.clockwise") })
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    
                    Divider().opacity(0.3)
                    
                    // File Sync Section
                    VStack(alignment: .leading, spacing: 10) {
                        Label(title: { Text("SHARED_FOLDER", bundle: .clawsy) }, icon: { Image(systemName: "folder.badge.plus") })
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                        
                        // Path display
                        Text(sharedFolderPath.isEmpty ? "None" : sharedFolderPath)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
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
                .padding(20)
            }
            .background(Color.black.opacity(0.02))
            
            Divider().opacity(0.3)
            
            // Footer
            HStack {
                Text("VIBRANT_SECURE", bundle: .clawsy)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Auto-saves")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.03))
        }
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
    
    // MARK: - SSH Key Management
    
    private var sshKeyInstalled: Bool {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroup) else { return false }
        let keyURL = groupURL.appendingPathComponent("clawsy_ssh_key")
        return FileManager.default.fileExists(atPath: keyURL.path)
    }
    
    private func selectSshKey() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.message = "Select your SSH private key"
            panel.prompt = "Import"
            panel.showsHiddenFiles = true
            
            // Start in ~/.ssh by default
            let sshDir = NSHomeDirectory() + "/.ssh"
            if FileManager.default.fileExists(atPath: sshDir) {
                panel.directoryURL = URL(fileURLWithPath: sshDir)
            }
            
            NSApp.activate(ignoringOtherApps: true)
            
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                
                guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroup) else {
                    print("Failed to get app group container")
                    return
                }
                
                let destURL = groupURL.appendingPathComponent("clawsy_ssh_key")
                
                do {
                    // Remove existing key if present
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destURL)
                    // Set restrictive permissions
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destURL.path)
                    print("SSH key imported successfully")
                } catch {
                    print("Failed to import SSH key: \(error)")
                }
            }
        }
    }
    
    private func removeSshKey() {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroup) else { return }
        let keyURL = groupURL.appendingPathComponent("clawsy_ssh_key")
        try? FileManager.default.removeItem(at: keyURL)
    }
}
