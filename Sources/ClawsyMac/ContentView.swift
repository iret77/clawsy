import SwiftUI
import UserNotifications
import ClawsyShared

struct ContentView: View {
    // Host Manager — manages multiple hosts and their NetworkManagers
    @StateObject private var hostManager = HostManager()
    @StateObject private var taskStore = TaskStore()
    @EnvironmentObject var appDelegate: AppDelegate
    
    @State private var showingSettings = false
    @State private var showingLog = false
    @State private var showingMetadata = false
    @State private var showingMissionControl = false
    @State private var ruleEditorFolderPath: String? = nil
    @State private var showingScreenshotMenu = false
    @State private var showingCameraMenu = false
    @State private var availableCameras: [[String: Any]] = []
    @AppStorage("activeCameraId", store: SharedConfig.sharedDefaults) private var activeCameraId = ""
    @State private var isScreenshotInteractive = false
    @State private var showingOnboarding = false
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var errorDismissed = false
    @State private var fixPromptCopied = false
    @State private var pairingCmdCopied = false
    @State private var serverSetupPromptCopied = false
    @State private var showingAddHostFromHeader = false
    
    // Persistent Configuration (UI State only) — kept for legacy SettingsView compatibility
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

    /// Convenience: the active NetworkManager from the host manager (nil when no host connected)
    private var network: NetworkManager? {
        hostManager.activeNetworkManager
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Host Switcher (always visible when multiple hosts) ---
            if hostManager.profiles.count > 1 {
                HostSwitcherView(hostManager: hostManager, onHostAdded: connectNewHost)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }
            Divider().opacity(0.3)
            // --- Header & Status ---
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l10n: "APP_NAME")
                            .font(.system(size: 13, weight: .semibold))
                        if let activeProfile = hostManager.activeProfile {
                            Text(activeProfile.name.isEmpty ? activeProfile.gatewayHost : activeProfile.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: activeProfile.color) ?? .secondary)
                        }
                    }
                    
                    Group {
                        if hostManager.connectionStatus == "STATUS_CONNECTING" {
                            Text(String(format: NSLocalizedString("STATUS_CONNECTING %lld", bundle: .clawsy, comment: ""), hostManager.connectionAttemptCount))
                        } else if hostManager.connectionStatus == "STATUS_RECONNECT_WAITING" && hostManager.retryCountdown > 0 {
                            Text(String(format: NSLocalizedString("STATUS_RECONNECT_COUNTDOWN %lld", bundle: .clawsy, comment: ""), hostManager.retryCountdown))
                        } else {
                            Text(LocalizedStringKey(hostManager.connectionStatus), bundle: .clawsy)
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

                // Status Indicator — colored per active host
                Circle()
                    .fill(getStatusColor())
                    .frame(width: 8, height: 8)
                    .shadow(color: getStatusColor().opacity(0.5), radius: 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            
            // --- Connection Error Banner ---
            if let connError = hostManager.connectionError, !errorDismissed {
                ConnectionErrorBanner(
                    error: connError,
                    fixPromptCopied: $fixPromptCopied,
                    onDismiss: { errorDismissed = true },
                    onOpenSettings: { showingSettings = true }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            // --- Pairing Approval Banner ---
            if hostManager.connectionStatus == "STATUS_AWAITING_PAIR_APPROVE" && !hostManager.pairingRequestId.isEmpty {
                PairingApprovalBanner(
                    requestId: hostManager.pairingRequestId,
                    copied: $pairingCmdCopied
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            // --- Server Setup Needed Banner ---
            if network?.serverSetupNeeded == true {
                ServerSetupBanner(copied: $serverSetupPromptCopied)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            
            Divider().opacity(0.5)

            // --- Empty State (no hosts configured) ---
            if hostManager.profiles.isEmpty {
                NoHostEmptyStateView(onAddHost: { showingAddHostFromHeader = true })
            }

            // --- Main Actions List ---
            // Order: Quick Send (most active) → Screenshot → Clipboard → Camera (most deliberate)
            if !hostManager.profiles.isEmpty { VStack(spacing: 2) {
                // Quick Send
                Button(action: { appDelegate.showQuickSend() }) {
                    MenuItemRow(icon: "paperplane.fill", title: "QUICK_SEND",
                                isEnabled: hostManager.isConnected,
                                shortcut: "⌘⇧\(SharedConfig.quickSendHotkey)")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                // Screenshot Group
                Button(action: { showingScreenshotMenu.toggle() }) {
                    MenuItemRow(icon: "camera", title: "SCREENSHOT", isEnabled: hostManager.isConnected, hasChevron: true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showingScreenshotMenu, arrowEdge: .trailing) {
                    VStack(spacing: 0) {
                        Button(action: {
                            showingScreenshotMenu = false
                            self.takeScreenshotAndSend(interactive: false)
                        }) {
                            MenuItemRow(icon: "rectangle.dashed", title: "FULL_SCREEN", isEnabled: hostManager.isConnected, shortcut: "⌘⇧\(SharedConfig.screenshotFullHotkey)")
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            showingScreenshotMenu = false
                            self.takeScreenshotAndSend(interactive: true)
                        }) {
                            MenuItemRow(icon: "plus.viewfinder", title: "INTERACTIVE_AREA", isEnabled: hostManager.isConnected, shortcut: "⌘⇧\(SharedConfig.screenshotAreaHotkey)")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(4)
                    .frame(width: 200)
                }

                // Clipboard
                Button(action: handleManualClipboardSend) {
                    MenuItemRow(icon: "doc.on.clipboard", title: "PUSH_CLIPBOARD",
                                isEnabled: hostManager.isConnected,
                                shortcut: "⌘⇧\(SharedConfig.pushClipboardHotkey)")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                // Camera Group
                Button(action: {
                    if !availableCameras.isEmpty {
                        // Ensure a camera is always selected before opening menu
                        let knownIds = availableCameras.compactMap { $0["id"] as? String }
                        if activeCameraId.isEmpty || !knownIds.contains(activeCameraId) {
                            if let first = availableCameras.first, let id = first["id"] as? String {
                                activeCameraId = id
                                SharedConfig.sharedDefaults.set(first["name"] as? String ?? "", forKey: "activeCameraName")
                            }
                        }
                        showingCameraMenu.toggle()
                    }
                }) {
                    MenuItemRow(icon: "video.fill", title: "CAMERA", isEnabled: hostManager.isConnected && !availableCameras.isEmpty, hasChevron: true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showingCameraMenu, arrowEdge: .trailing) {
                    CameraMenuView(
                        cameras: availableCameras,
                        activeCameraId: $activeCameraId,
                        isConnected: hostManager.isConnected,
                        onTakePhoto: { camId, camName in
                            showingCameraMenu = false
                            if let nm = network {
                                takePhotoWithActive(camId: camId, camName: camName, network: nm)
                            }
                        }
                    )
                }
                
                Divider().padding(.vertical, 4).opacity(0.5)
                
                // Connection Control
                Button(action: toggleConnection) {
                    MenuItemRow(
                        icon: hostManager.isConnected ? "power" : "bolt.slash.fill",
                        title: hostManager.isConnected ? "DISCONNECT" : "CONNECT",
                        color: hostManager.isConnected ? .red : .blue
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Divider().padding(.vertical, 4).opacity(0.5)

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
                    if let nm = network {
                        MissionControlView(taskStore: taskStore, networkManager: nm)
                    }
                }

                // Settings (contains Debug Log + Setup Wizard inside)
                Button(action: { showingSettings.toggle() }) {
                    MenuItemRow(icon: "gearshape.fill", title: "SETTINGS", isEnabled: true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showingSettings, arrowEdge: .trailing) {
                    SettingsView(
                        hostManager: hostManager,
                        isPresented: $showingSettings,
                        onShowDebugLog: {
                            showingSettings = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { showingLog = true }
                        },
                        onShowOnboarding: {
                            showingSettings = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                appDelegate.openOnboardingWindow(onboardingCompleted: $onboardingCompleted)
                            }
                        },
                        onShowMetadata: {
                            showingSettings = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { showingMetadata = true }
                        },
                        onHostAdded: connectNewHost
                    )
                    .frame(width: 380)
                }
                // Debug Log popover (triggered from Settings)
                .background(
                    Color.clear
                        .popover(isPresented: $showingLog, arrowEdge: .trailing) {
                            DebugLogView(logText: network?.rawLog ?? "", isPresented: $showingLog)
                                .frame(width: 400, height: 300)
                        }
                )
                // Metadata popover (triggered from Settings)
                .background(
                    Color.clear
                        .popover(isPresented: $showingMetadata, arrowEdge: .trailing) {
                            if let nm = network {
                                MetadataView(network: nm, isPresented: $showingMetadata)
                                    .frame(width: 350, height: 320)
                            }
                        }
                )

                Divider().padding(.vertical, 4).opacity(0.5)
                
                // Quit
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    MenuItemRow(icon: "xmark.circle.fill", title: "QUIT", isEnabled: true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(6)
            } // end if !hostManager.profiles.isEmpty
        }
        .frame(width: 300)
        .onAppear {
            // Link HostManager to AppDelegate for QuickSend, hotkeys, etc.
            appDelegate.hostManager = hostManager
            appDelegate.networkManager = hostManager.activeNetworkManager

            // Load cameras once on appear (not in body — AVCaptureDevice on main thread every render)
            DispatchQueue.global(qos: .userInitiated).async {
                let cameras = CameraManager.listCameras()
                DispatchQueue.main.async {
                    availableCameras = cameras
                    // Auto-select first camera if none saved or saved ID no longer exists
                    let knownIds = cameras.compactMap { $0["id"] as? String }
                    if activeCameraId.isEmpty || !knownIds.contains(activeCameraId) {
                        if let first = cameras.first, let id = first["id"] as? String {
                            activeCameraId = id
                            SharedConfig.sharedDefaults.set(first["name"] as? String ?? "", forKey: "activeCameraName")
                        }
                    }
                }
            }

            // Listen for FinderSync actions via Darwin notification
            ActionBridge.observe {
                if let action = ActionBridge.consumeAction() {
                    handleFinderSyncAction(action)
                }
            }
            
            // Connect all configured hosts
            if !hostManager.profiles.isEmpty {
                hostManager.connectAll { nm, profile in
                    setupCallbacksForHost(nm: nm, profile: profile)
                }
            } else if !serverHost.isEmpty && !serverToken.isEmpty {
                // Legacy fallback: no profiles yet, create a transient profile and register in hostManager
                let legacyProfile = HostProfile(
                    name: serverHost,
                    gatewayHost: serverHost,
                    gatewayPort: serverPort,
                    serverToken: serverToken,
                    sshUser: sshUser,
                    useSshFallback: useSshFallback,
                    sharedFolderPath: sharedFolderPath
                )
                hostManager.profiles = [legacyProfile]
                hostManager.activeHostId = legacyProfile.id
                hostManager.connectAll { nm, profile in
                    setupCallbacksForHost(nm: nm, profile: profile)
                }
                appDelegate.networkManager = hostManager.activeNetworkManager
            }
            
            // Validate & provision active host's shared folder
            if let active = hostManager.activeProfile, !active.sharedFolderPath.isEmpty {
                let resolved = active.sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
                if ClawsyFileManager.folderExists(at: resolved) {
                    DispatchQueue.global(qos: .background).async {
                        ClawsyManifestManager.provisionAll(in: resolved)
                    }
                }
            }
            
            setupFileWatcher()
            appDelegate.updateMenuBarIcon()
        }
        .onChange(of: sharedFolderPath) { _ in
            setupFileWatcher()
        }
        .onChange(of: hostManager.connectionError) { newError in
            // Reset dismiss state when error type changes or clears
            if newError == nil {
                errorDismissed = false
            } else {
                errorDismissed = false
                fixPromptCopied = false
            }
        }
        .onChange(of: hostManager.activeHostId) { _ in
            // When active host changes, update AppDelegate references and menu bar icon
            appDelegate.networkManager = hostManager.activeNetworkManager
            appDelegate.updateMenuBarIcon()
            setupFileWatcher()
            // Clear agent info — it belongs to the previous host
            agentModel = nil
            agentName = nil
            taskStore.clearAll()
            // Start poller for the new active host
            if let nm = hostManager.activeNetworkManager, nm.isConnected {
                nm.startStatePoller()
            }
        }
        .onChange(of: hostManager.isConnected) { _ in
            // Sync AppDelegate's networkManager when connection state changes
            // so hotkeys always use the current active NetworkManager
            appDelegate.networkManager = hostManager.activeNetworkManager
            appDelegate.updateMenuBarIcon()
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
        .sheet(isPresented: $showingAddHostFromHeader) {
            AddHostSheet(hostManager: hostManager, isPresented: $showingAddHostFromHeader, onHostAdded: connectNewHost)
        }

    }
    
    // --- Actions ---
    
    func handleFinderSyncAction(_ action: PendingAction) {
        let activeNM = hostManager.activeNetworkManager
        let activeFolderPath = hostManager.activeProfile?.sharedFolderPath ?? sharedFolderPath
        
        switch action.kind {
        case "open_rule_editor":
            ruleEditorFolderPath = action.folderPath
        case "send_telemetry":
            if let nm = activeNM, nm.isConnected {
                if let jsonString = ClawsyEnvelopeBuilder.build(type: "telemetry", content: "📡 Telemetrie von \(action.folderPath)", includeTelemetry: true) {
                    nm.sendServiceEvent(message: jsonString)
                }
            }
        case "run_actions":
            guard let nm = activeNM, nm.isConnected else { break }
            let folderURL = URL(fileURLWithPath: action.folderPath)
            let files = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
            for fileURL in files {
                let fileName = fileURL.lastPathComponent
                guard !fileName.hasPrefix(".") else { continue }
                let rules = ClawsyManifestManager.matchingRules(for: fileName, in: action.folderPath, trigger: "manual")
                let resolvedPath = activeFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
                for rule in rules {
                    let relativePath = fileURL.path.replacingOccurrences(of: resolvedPath, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    switch rule.action {
                    case "send_to_agent":
                        nm.sendEvent(kind: "file.rule_triggered", payload: [
                            "trigger": "manual",
                            "fileName": fileName,
                            "relativePath": relativePath,
                            "ruleId": rule.id,
                            "prompt": rule.prompt,
                            "folderPath": activeFolderPath
                        ])
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
        if hostManager.isConnected { return .green }
        if hostManager.connectionStatus.contains("CONNECTING") || hostManager.connectionStatus.contains("STARTING") { return .orange }
        return .red
    }
    
    func toggleConnection() {
        if hostManager.isConnected {
            hostManager.disconnectAll()
        } else {
            if !hostManager.profiles.isEmpty {
                hostManager.connectAll { nm, profile in
                    setupCallbacksForHost(nm: nm, profile: profile)
                }
            } else {
                // Legacy single-host path
                let nm = NetworkManager()
                setupCallbacksLegacy(nm)
                nm.configure(host: serverHost, port: serverPort, token: serverToken, sshUser: sshUser, fallback: useSshFallback)
                nm.connect()
                appDelegate.networkManager = nm
            }
        }
    }
    
    // Manual screenshot trigger
    func takeScreenshotAndSend(interactive: Bool) {
        guard let nm = network else { return }
        // Close the popover — use close() directly, performClose can fail when called from within the popover
        appDelegate.popover.close()
        // Wait for the popover to fully disappear before capturing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let b64 = ScreenshotManager.takeScreenshot(interactive: interactive) {
                nm.sendScreenshot(base64: b64, mimeType: "image/jpeg")
                self.appDelegate.showStatusHUD(icon: "camera.fill", title: "SCREENSHOT_SENT")
            }
        }
    }
    
    func takePhotoWithActive(camId: String, camName: String, network: NetworkManager) {
        CameraManager.takePhoto(deviceId: camId.isEmpty ? nil : camId) { b64 in
            guard let b64 = b64 else {
                DispatchQueue.main.async {
                    appDelegate.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "CAPTURE_FAILED")
                }
                return
            }
            network.sendPhoto(base64: b64, deviceName: camName)
            DispatchQueue.main.async {
                appDelegate.showStatusHUD(icon: "camera.fill", title: "PHOTO_SENT")
            }
        }
    }

        func handleManualClipboardSend() {
        guard let activeNM = hostManager.activeNetworkManager else { return }
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
                // Clipboard → clawsy-service only (silent background context)
                activeNM.sendServiceEvent(message: jsonString)
                appDelegate.showStatusHUD(icon: "doc.on.clipboard.fill", title: "CLIPBOARD_SENT")
            }
        }
    }
    
    func setupFileWatcher() {
        fileWatcher?.stop()
        let activeFolderPath = hostManager.activeProfile?.sharedFolderPath ?? sharedFolderPath
        let resolvedPath = activeFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        guard !activeFolderPath.isEmpty, ClawsyFileManager.folderExists(at: resolvedPath) else { return }
        
        let watcher = FileWatcher(url: URL(fileURLWithPath: resolvedPath))
        watcher.typedCallback = { [weak hostManager] changedPath, eventType in
            guard let activeNM = hostManager?.activeNetworkManager else { return }
            let activeFolder = hostManager?.activeProfile?.sharedFolderPath ?? ""

            // agent.status and agent.info are now delivered via WebSocket events (see onTaskUpdate / onAgentInfoUpdate)
            // Skip these files to avoid stale file reads
            if changedPath.hasSuffix(".agent_status.json") || changedPath.hasSuffix(".agent_info.json") {
                return
            }

            // Extract relative path for the agent
            let relativePath = changedPath.replacingOccurrences(of: resolvedPath, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            // --- .clawsy Rule Matching & Execution ---
            let changedURL = URL(fileURLWithPath: changedPath)
            let fileName = changedURL.lastPathComponent
            let parentFolder = changedURL.deletingLastPathComponent().path
            let triggerName = eventType.rawValue  // "file_added" or "file_changed"

            // Skip hidden files and .clawsy manifests themselves
            if !fileName.hasPrefix(".") {
                let matchedRules = ClawsyManifestManager.matchingRules(for: fileName, in: parentFolder, trigger: triggerName)
                for rule in matchedRules {
                    switch rule.action {
                    case "send_to_agent":
                        // Send as node.event with event: "file.rule_triggered"
                        // Includes filename, rule id, prompt, and file path for agent processing
                        activeNM.sendEvent(kind: "file.rule_triggered", payload: [
                            "trigger": triggerName,
                            "fileName": fileName,
                            "relativePath": relativePath,
                            "ruleId": rule.id,
                            "prompt": rule.prompt,
                            "folderPath": activeFolder
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

            // General file sync event (always fires for non-hidden files)
            activeNM.sendEvent(kind: "file.sync_triggered", payload: [
                "path": activeFolder,
                "changedPath": relativePath,
                "eventType": triggerName
            ])
        }
        watcher.start()
        self.fileWatcher = watcher
    }
    
    /// Connect a newly added host and set up its callbacks
    func connectNewHost(_ profile: HostProfile) {
        hostManager.connectHost(profile.id) { nm, prof in
            setupCallbacksForHost(nm: nm, profile: prof)
        }
    }

    /// Set up callbacks for a specific host's NetworkManager
    func setupCallbacksForHost(nm: NetworkManager, profile: HostProfile) {
        nm.onScreenshotRequested = { interactive, requestId in
            DispatchQueue.main.async {
                self.appDelegate.showScreenshotRequest(
                    requestedInteractive: interactive,
                    onConfirm: { userInteractive in
                        if let b64 = ScreenshotManager.takeScreenshot(interactive: userInteractive) {
                            nm.sendResponse(id: requestId, result: ["format": "jpeg", "base64": b64])
                        } else {
                            nm.sendError(id: requestId, code: -1, message: "Screenshot failed")
                        }
                    },
                    onCancel: {
                        nm.sendError(id: requestId, code: -1, message: "User denied screenshot")
                    }
                )
            }
        }
        
        nm.onClipboardReadRequested = { requestId in
            if let content = ClipboardManager.getClipboardContent() {
                nm.sendResponse(id: requestId, result: ["text": content])
            } else {
                nm.sendError(id: requestId, code: -1, message: "Clipboard empty or unavailable")
            }
        }
        
        nm.onClipboardWriteRequested = { content, requestId in
            DispatchQueue.main.async {
                self.appDelegate.showClipboardRequest(content: content, onConfirm: {
                    ClipboardManager.setClipboardContent(content)
                    nm.sendResponse(id: requestId, result: ["status": "ok"])
                }, onCancel: {
                    nm.sendError(id: requestId, code: -1, message: "User denied clipboard write")
                })
            }
        }
        
        nm.onFileSyncRequested = { filename, operation, onConfirm, onCancel in
            DispatchQueue.main.async {
                self.appDelegate.showFileSyncRequest(filename: filename, operation: operation, onConfirm: { duration in
                    onConfirm(duration)
                }, onCancel: {
                    onCancel()
                })
            }
        }

        nm.onCameraPreviewRequested = { image, onConfirm, onCancel in
            self.appDelegate.showCameraPreview(image: image, onConfirm: onConfirm, onCancel: onCancel)
        }
        
        // Wire agent info updates only for the active host
        nm.onAgentInfoUpdate = { [self] model, name in
            // Only update UI if this is the active host
            if nm.hostProfileId == self.hostManager.activeHostId {
                DispatchQueue.main.async {
                    self.agentModel = model
                    self.agentName = name
                }
            }
        }

        nm.onTaskUpdate = { [self] agent, title, progress, status in
            if nm.hostProfileId == self.hostManager.activeHostId {
                self.taskStore.updateTask(agentName: agent, title: title, progress: progress, statusText: status)
            }
        }
        
        // Start state poller when handshake completes
        nm.onHandshakeComplete = { [self] in
            if nm.hostProfileId == self.hostManager.activeHostId {
                nm.startStatePoller()
            }
            // Trigger file sync
            nm.sendEvent(kind: "file.sync_triggered", payload: ["path": profile.sharedFolderPath])
        }
    }
    
    /// Legacy callback setup for single NetworkManager (no HostManager)
    func setupCallbacksLegacy(_ network: NetworkManager) {
        network.onScreenshotRequested = { interactive, requestId in
            DispatchQueue.main.async {
                self.appDelegate.showScreenshotRequest(
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
                self.appDelegate.showClipboardRequest(content: content, onConfirm: {
                    ClipboardManager.setClipboardContent(content)
                    network.sendResponse(id: requestId, result: ["status": "ok"])
                }, onCancel: {
                    network.sendError(id: requestId, code: -1, message: "User denied clipboard write")
                })
            }
        }
        
        network.onFileSyncRequested = { filename, operation, onConfirm, onCancel in
            DispatchQueue.main.async {
                self.appDelegate.showFileSyncRequest(filename: filename, operation: operation, onConfirm: { duration in
                    onConfirm(duration)
                }, onCancel: {
                    onCancel()
                })
            }
        }

        network.onCameraPreviewRequested = { image, onConfirm, onCancel in
            self.appDelegate.showCameraPreview(image: image, onConfirm: onConfirm, onCancel: onCancel)
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
                    Text(l10n: "DEBUG_LOG_TITLE")
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
                    Text(l10n: "NO_DATA")
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
            .scrollIndicators(.visible)
            .background(Color.black.opacity(0.05))
            
            Divider().opacity(0.3)
            
            // Footer
            HStack {
                Text(l10n: "SELECT_TEXT_COPY")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }) {
                    Text(l10n: "COPY_ALL")
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
                Label(title: { Text(l10n: "LAST_METADATA") }, icon: { Image(systemName: "info.circle.fill") })
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
                        Text(l10n: "EXTENDED_CONTEXT")
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
                        Text(l10n: "EXTENDED_CONTEXT_DISABLED")
                            .font(.system(size: 10).italic())
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.visible)
            .background(Color.black.opacity(0.05))
            
            Divider().opacity(0.3)
            
            // Footer
            HStack {
                Text(l10n: "METADATA_VIEW_DESC")
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
    /// Host manager — the single source of truth for host-specific settings (v0.6.1+)
    @ObservedObject var hostManager: HostManager
    @Binding var isPresented: Bool
    var onShowDebugLog: (() -> Void)? = nil
    var onShowOnboarding: (() -> Void)? = nil
    var onShowMetadata: (() -> Void)? = nil
    var onHostAdded: ((HostProfile) -> Void)? = nil

    /// Local editable copy of the active host profile; committed on dismiss
    @State private var editedProfile: HostProfile = HostProfile(
        name: "", gatewayHost: "", gatewayPort: "18789", serverToken: ""
    )

    @State private var showingAddHost = false
    @State private var hostToDelete: HostProfile? = nil
    @State private var showDeleteConfirm = false
    @State private var selectedTab = 0

    // Non-host global settings (shared across all hosts)
    @AppStorage("extendedContextEnabled", store: SharedConfig.sharedDefaults) private var extendedContextEnabled = false
    @AppStorage("quickSendHotkey", store: SharedConfig.sharedDefaults) private var quickSendHotkey = "K"
    @AppStorage("pushClipboardHotkey", store: SharedConfig.sharedDefaults) private var pushClipboardHotkey = "V"
    @AppStorage("cameraHotkey", store: SharedConfig.sharedDefaults) private var cameraHotkey = "P"
    @AppStorage("screenshotFullHotkey", store: SharedConfig.sharedDefaults) private var screenshotFullHotkey = "S"
    @AppStorage("screenshotAreaHotkey", store: SharedConfig.sharedDefaults) private var screenshotAreaHotkey = "A"

    // Legacy AppStorage fallback — only used when hostManager.profiles.isEmpty
    @AppStorage("serverHost", store: SharedConfig.sharedDefaults) private var legacyServerHost = "agenthost"
    @AppStorage("serverPort", store: SharedConfig.sharedDefaults) private var legacyServerPort = "18789"
    @AppStorage("serverToken", store: SharedConfig.sharedDefaults) private var legacyServerToken = ""
    @AppStorage("sshUser", store: SharedConfig.sharedDefaults) private var legacySshUser = ""
    @AppStorage("useSshFallback", store: SharedConfig.sharedDefaults) private var legacyUseSshFallback = true
    @AppStorage("sharedFolderPath", store: SharedConfig.sharedDefaults) private var legacySharedFolderPath = "~/Documents/Clawsy"

    @ObservedObject var updateManager = UpdateManager.shared

    /// Save the edited profile back to HostManager (or legacy keys) and close the popover.
    private func saveAndDismiss() {
        if hostManager.profiles.isEmpty {
            legacyServerHost = editedProfile.gatewayHost
            legacyServerPort = editedProfile.gatewayPort
            legacyServerToken = editedProfile.serverToken
            legacySshUser = editedProfile.sshUser
            legacyUseSshFallback = editedProfile.useSshFallback
            legacySharedFolderPath = editedProfile.sharedFolderPath
        } else {
            // Ensure name falls back to host if blank
            if editedProfile.name.trimmingCharacters(in: .whitespaces).isEmpty {
                editedProfile.name = editedProfile.gatewayHost
            }
            hostManager.updateHost(editedProfile)
        }
        isPresented = false
    }

    func selectFolder() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = NSLocalizedString("SELECT_SHARED_FOLDER", bundle: .clawsy, comment: "")
            panel.resolvesAliases = true

            // Start at current folder or Home
            if !editedProfile.sharedFolderPath.isEmpty {
                let resolved = editedProfile.sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
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
                            self.editedProfile.sharedFolderPath = path
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
                Text(l10n: "SETTINGS_TITLE")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: saveAndDismiss) {
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

            // Content — Tabbed Layout
            TabView(selection: $selectedTab) {

                // ━━ Tab 1: Connection ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                VStack(alignment: .leading, spacing: 24) {

                        // ── Host Management Section ──────────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(title: { Text(l10n: "HOSTS") }, icon: { Image(systemName: "server.rack") })
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.indigo)
                                Spacer()
                                Button(action: { showingAddHost = true }) {
                                    Label(title: { Text(l10n: "ADD_HOST") }, icon: { Image(systemName: "plus.circle.fill") })
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            ForEach(hostManager.profiles) { profile in
                                let isActive = profile.id == hostManager.activeHostId
                                let nm = hostManager.networkManagers[profile.id]
                                let isConnected = nm?.isConnected ?? false
                                let isConnecting = nm?.connectionStatus.contains("CONNECTING") ?? false || nm?.connectionStatus.contains("STARTING") ?? false
                                let hostColor = Color(hex: profile.color) ?? .red

                                HStack(spacing: 8) {
                                    // Color dot
                                    Circle().fill(hostColor).frame(width: 8, height: 8)

                                    // Name
                                    Text(profile.name.isEmpty ? profile.gatewayHost : profile.name)
                                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                        .lineLimit(1)

                                    Spacer()

                                    // Connection status badge
                                    if isConnected {
                                        Circle().fill(Color.green).frame(width: 6, height: 6)
                                    } else if isConnecting {
                                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                                    } else {
                                        Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                                    }

                                    // Active indicator
                                    if isActive {
                                        Text(l10n: "ACTIVE")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(hostColor)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(hostColor.opacity(0.12))
                                            .cornerRadius(3)
                                    }

                                    // Delete button (disabled if only 1 host)
                                    Button(action: {
                                        hostToDelete = profile
                                        showDeleteConfirm = true
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(hostManager.profiles.count <= 1)
                                    .opacity(hostManager.profiles.count <= 1 ? 0.3 : 1.0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(isActive ? hostColor.opacity(0.08) : Color.clear)
                                .cornerRadius(7)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(isActive ? hostColor.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if !isActive {
                                        hostManager.updateHost(editedProfile) // save current edits first
                                        hostManager.switchActiveHost(to: profile.id)
                                        if let newActive = hostManager.activeProfile {
                                            editedProfile = newActive
                                        }
                                    }
                                }
                            }
                        }

                        Divider().opacity(0.3)

                        // ── Gateway Section ──────────────────────────────────────
                        VStack(alignment: .leading, spacing: 10) {
                            Label(title: { Text(l10n: "GATEWAY") }, icon: { Image(systemName: "antenna.radiowaves.left.and.right") })
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.blue)

                            // Host name + color picker row
                            HStack(spacing: 8) {
                                TextField(text: $editedProfile.name) {
                                    Text(l10n: "HOST_NAME")
                                }
                                .textFieldStyle(.roundedBorder)

                                // Color picker — 8 preset circles
                                HStack(spacing: 5) {
                                    ForEach(HostProfile.defaultColors, id: \.self) { hex in
                                        let c = Color(hex: hex) ?? .red
                                        let isSelected = editedProfile.color == hex
                                        Circle()
                                            .fill(c)
                                            .frame(width: isSelected ? 16 : 12, height: isSelected ? 16 : 12)
                                            .overlay(Circle().stroke(Color.primary.opacity(isSelected ? 0.4 : 0), lineWidth: 1.5))
                                            .onTapGesture { editedProfile.color = hex }
                                            .animation(.easeInOut(duration: 0.1), value: isSelected)
                                    }
                                }
                            }

                            HStack(spacing: 8) {
                                TextField(text: $editedProfile.gatewayHost) {
                                    Text(l10n: "HOST")
                                }
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                                TextField(text: $editedProfile.gatewayPort) {
                                    Text(l10n: "PORT")
                                }
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 80)
                            }

                            SecureField(text: $editedProfile.serverToken) {
                                Text(l10n: "TOKEN")
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                            // Onboarding guide — 2-step setup
                            VStack(alignment: .leading, spacing: 6) {
                                Text(l10n: "CONNECTION_GUIDE_TITLE")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Label {
                                    Text(l10n: "CONNECTION_GUIDE_STEP1")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Text("1.")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 16, alignment: .leading)
                                }
                                
                                Label {
                                    Text(l10n: "CONNECTION_GUIDE_STEP2")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Text("2.")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 16, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(8)
                            .padding(.top, 4)

                            // Re-Pair button — clears deviceToken and forces fresh pairing
                            Button(action: {
                                hostManager.repairActiveConnection()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 12))
                                    Text(l10n: "REPAIR_CONNECTION")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .help(NSLocalizedString("REPAIR_CONNECTION_HELP", bundle: .clawsy, comment: ""))
                        }

                        Divider().opacity(0.3)

                        // SSH Fallback Section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(title: { Text(l10n: "SSH_FALLBACK") }, icon: { Image(systemName: "lock.shield") })
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.orange)
                                Spacer()
                                Toggle("", isOn: $editedProfile.useSshFallback)
                                    .toggleStyle(.switch)
                                    .scaleEffect(0.7)
                            }

                            TextField(text: $editedProfile.sshUser) {
                                Text(l10n: "SSH_USER")
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .disabled(!editedProfile.useSshFallback)
                            .opacity(editedProfile.useSshFallback ? 1.0 : 0.5)

                            // SSH-Only Mode toggle (only visible when SSH fallback is enabled and user is set)
                            if editedProfile.useSshFallback && !editedProfile.sshUser.isEmpty {
                                Divider().opacity(0.2)
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(l10n: "SSH_ONLY_MODE")
                                            .font(.system(size: 12, weight: .medium))
                                        Text(l10n: "SSH_ONLY_MODE_DESC")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $editedProfile.sshOnly)
                                        .toggleStyle(.switch)
                                        .scaleEffect(0.7)
                                }
                            }

                            Text(l10n: "SSH_FALLBACK_DESC")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(20)
                .tag(0)
                .tabItem {
                    Label(NSLocalizedString("SETTINGS_TAB_CONNECTION", bundle: .clawsy, comment: ""), systemImage: "network")
                }

                // ━━ Tab 2: Features ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                VStack(alignment: .leading, spacing: 24) {

                        // Extended Context Section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(title: { Text(l10n: "EXTENDED_CONTEXT") }, icon: { Image(systemName: "chart.bar.doc.horizontal") })
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
                            
                            Text(l10n: "EXTENDED_CONTEXT_DESC")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Divider().opacity(0.3)
                        
                        // Hotkeys Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center) {
                                Label(title: { Text(l10n: "HOTKEYS") }, icon: { Image(systemName: "keyboard") })
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.purple)
                                Spacer()
                                // Accessibility status badge + grant button
                                if AXIsProcessTrusted() {
                                    Label(NSLocalizedString("ACCESSIBILITY_GRANTED", bundle: .clawsy, comment: ""), systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                } else {
                                    Button(action: {
                                        NSApp.delegate.flatMap { $0 as? AppDelegate }?.requestAccessibilityPermission()
                                    }) {
                                        Label(NSLocalizedString("GRANT_ACCESSIBILITY", bundle: .clawsy, comment: ""), systemImage: "exclamationmark.shield.fill")
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .controlSize(.small)
                                }
                            }
                            
                            HStack {
                                Text(l10n: "HOTKEY_QUICK_SEND")
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
                                Text(l10n: "HOTKEY_PUSH_CLIPBOARD")
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

                            HStack {
                                Text(l10n: "HOTKEY_CAMERA")
                                    .font(.system(size: 12))
                                Spacer()
                                Text("⌘ + ⇧ +")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("", text: $cameraHotkey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced, weight: .bold))
                                    .frame(width: 44)
                                    .multilineTextAlignment(.center)
                                    .onChange(of: cameraHotkey) { newValue in
                                        cameraHotkey = String(newValue.prefix(1)).uppercased()
                                    }
                            }

                            HStack {
                                Text(l10n: "HOTKEY_SCREENSHOT_FULL")
                                    .font(.system(size: 12))
                                Spacer()
                                Text("⌘ + ⇧ +")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("", text: $screenshotFullHotkey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced, weight: .bold))
                                    .frame(width: 44)
                                    .multilineTextAlignment(.center)
                                    .onChange(of: screenshotFullHotkey) { newValue in
                                        screenshotFullHotkey = String(newValue.prefix(1)).uppercased()
                                    }
                            }

                            HStack {
                                Text(l10n: "HOTKEY_SCREENSHOT_AREA")
                                    .font(.system(size: 12))
                                Spacer()
                                Text("⌘ + ⇧ +")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("", text: $screenshotAreaHotkey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced, weight: .bold))
                                    .frame(width: 44)
                                    .multilineTextAlignment(.center)
                                    .onChange(of: screenshotAreaHotkey) { newValue in
                                        screenshotAreaHotkey = String(newValue.prefix(1)).uppercased()
                                    }
                            }
                        }
                        
                        Divider().opacity(0.3)
                        
                        // File Sync Section
                        VStack(alignment: .leading, spacing: 10) {
                            Label(title: { Text(l10n: "SHARED_FOLDER") }, icon: { Image(systemName: "folder.badge.plus") })
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.green)
                            
                            // Path display
                            Text(editedProfile.sharedFolderPath.isEmpty ? "None" : editedProfile.sharedFolderPath)
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
                                    Label(title: { Text(l10n: "SELECT_FOLDER_BUTTON") }, icon: { Image(systemName: "folder.fill.badge.plus") })
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)

                                if !editedProfile.sharedFolderPath.isEmpty {
                                    Button(action: {
                                        let resolved = editedProfile.sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: resolved)
                                    }) {
                                        Label(title: { Text(l10n: "SHOW_IN_FINDER") }, icon: { Image(systemName: "magnifyingglass") })
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                }
                            }
                        }
                    }
                    .padding(20)
                .tag(1)
                .tabItem {
                    Label(NSLocalizedString("SETTINGS_TAB_FEATURES", bundle: .clawsy, comment: ""), systemImage: "gearshape.2")
                }

                // ━━ Tab 3: Updates ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                VStack(alignment: .leading, spacing: 24) {

                        // Updates Section
                        VStack(alignment: .leading, spacing: 10) {
                            Label(title: { Text(l10n: "UPDATES") }, icon: { Image(systemName: "arrow.triangle.2.circlepath") })
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
                                        Label(title: { Text(l10n: "CHECK_NOW") }, icon: { Image(systemName: "arrow.clockwise") })
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .padding(20)
                .tag(2)
                .tabItem {
                    Label(NSLocalizedString("SETTINGS_TAB_UPDATES", bundle: .clawsy, comment: ""), systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            
            Divider().opacity(0.3)
            
            // Footer
            VStack(spacing: 0) {
                Divider().opacity(0.3)
                HStack(spacing: 4) {
                    // Icon-only buttons with tooltips — avoids text wrapping
                    Button(action: { onShowMetadata?() }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help(NSLocalizedString("LAST_METADATA", bundle: .clawsy, comment: ""))

                    Button(action: { onShowDebugLog?() }) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 13))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help(NSLocalizedString("DEBUG_LOG", bundle: .clawsy, comment: ""))

                    Button(action: { onShowOnboarding?() }) {
                        Image(systemName: "checklist")
                            .font(.system(size: 13))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help(NSLocalizedString("SETUP", bundle: .clawsy, comment: ""))

                    Spacer()

                    Text(l10n: "VIBRANT_SECURE")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.03))
            }
        }
        .onAppear {
            if let active = hostManager.activeProfile {
                editedProfile = active
            } else {
                editedProfile = HostProfile(
                    name: legacyServerHost,
                    gatewayHost: legacyServerHost,
                    gatewayPort: legacyServerPort,
                    serverToken: legacyServerToken,
                    sshUser: legacySshUser,
                    useSshFallback: legacyUseSshFallback,
                    sharedFolderPath: legacySharedFolderPath
                )
            }
        }
        .sheet(isPresented: $showingAddHost) {
            AddHostSheet(hostManager: hostManager, isPresented: $showingAddHost, onHostAdded: onHostAdded)
        }
        .alert(
            String(format: NSLocalizedString("DELETE_HOST_TITLE %@", bundle: .clawsy, comment: ""),
                   hostToDelete?.name ?? hostToDelete?.gatewayHost ?? ""),
            isPresented: $showDeleteConfirm,
            actions: {
                Button(NSLocalizedString("DELETE_HOST_CONFIRM", bundle: .clawsy, comment: ""), role: .destructive) {
                    if let h = hostToDelete {
                        hostManager.removeHost(id: h.id)
                        if let newActive = hostManager.activeProfile {
                            editedProfile = newActive
                        }
                    }
                    hostToDelete = nil
                }
                Button(NSLocalizedString("CANCEL", bundle: .clawsy, comment: ""), role: .cancel) {
                    hostToDelete = nil
                }
            },
            message: {
                Text(l10n: "DELETE_HOST_MESSAGE")
            }
        )
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }

}

// MARK: - Camera Menu Popover
struct CameraMenuView: View {
    let cameras: [[String: Any]]
    @Binding var activeCameraId: String
    let isConnected: Bool
    let onTakePhoto: (String, String) -> Void

    private var activeCam: [String: Any]? {
        cameras.first { ($0["id"] as? String) == activeCameraId } ?? cameras.first
    }
    private var activeCamId: String   { activeCam?["id"]   as? String ?? "" }
    private var activeCamName: String { activeCam?["name"] as? String ?? "Kamera" }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { onTakePhoto(activeCamId, activeCamName) }) {
                MenuItemRow(icon: "camera.fill", title: "TAKE_PHOTO", isEnabled: isConnected, shortcut: "⌘⇧\(SharedConfig.cameraHotkey)")
            }
            .buttonStyle(.plain)

            Divider().padding(.vertical, 2).opacity(0.5)

            ForEach(cameras.indices, id: \.self) { idx in
                let cam    = cameras[idx]
                let camId  = cam["id"]   as? String ?? ""
                let camName = cam["name"] as? String ?? "Kamera \(idx + 1)"
                Button(action: {
                    activeCameraId = camId
                    SharedConfig.sharedDefaults.set(camName, forKey: "activeCameraName")
                }) {
                    MenuItemRow(
                        icon: camId == activeCameraId ? "checkmark.circle.fill" : "circle",
                        title: camName,
                        isEnabled: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 220)
    }
}

// MARK: - Pairing Approval Banner

struct PairingApprovalBanner: View {
    let requestId: String
    @Binding var copied: Bool

    private var command: String { "openclaw devices approve \(requestId)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Text(l10n: "PAIRING_REQUIRED_TITLE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }

            // Description
            Text(l10n: "PAIRING_REQUIRED_DESC")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.85))

            // Command + Copy button
            HStack(spacing: 6) {
                Text(command)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .lineLimit(1)

                Spacer()

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        copied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(l10n: copied ? "PAIRING_COPIED" : "PAIRING_COPY_CMD")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(6)
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }

            // Hint
            Text(l10n: "PAIRING_REQUIRED_HINT")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.85), Color.indigo.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - Connection Error Banner

struct ConnectionErrorBanner: View {
    let error: ConnectionError
    @Binding var fixPromptCopied: Bool
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Text("Verbindungsfehler")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            // Title + Description
            VStack(alignment: .leading, spacing: 3) {
                Text(error.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                Text(error.description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Action buttons
            HStack(spacing: 8) {
                if let prompt = error.fixPrompt {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prompt, forType: .string)
                        fixPromptCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            fixPromptCopied = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: fixPromptCopied ? "checkmark" : "doc.on.clipboard")
                                .font(.system(size: 10))
                            Text(fixPromptCopied ? "✓ Kopiert!" : "Fix-Prompt kopieren")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(6)
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }

                if case .openSettings = error.fixAction {
                    Button(action: onOpenSettings) {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 10))
                            Text("Einstellungen")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(6)
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Color.red.opacity(0.85), Color.orange.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - Server Setup Needed Banner

struct ServerSetupBanner: View {
    @Binding var copied: Bool

    private let installPrompt = "OpenClaw Gateway is not reachable. Install OpenClaw from https://openclaw.ai and make sure the gateway service is running."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Text(l10n: "SERVER_SETUP_NEEDED_TITLE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }

            // Description
            Text(l10n: "SERVER_SETUP_NEEDED_DESC")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            // Copy button
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(installPrompt, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    copied = false
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 10))
                    Text(l10n: copied ? "SERVER_SETUP_PROMPT_COPIED" : "SERVER_SETUP_COPY_PROMPT")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.2))
                .cornerRadius(6)
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.85), Color.yellow.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - Host Switcher View (horizontal pill row)

struct HostSwitcherView: View {
    @ObservedObject var hostManager: HostManager
    var onHostAdded: ((HostProfile) -> Void)? = nil
    @State private var showingAddHost = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(hostManager.profiles) { profile in
                    let isActive = profile.id == hostManager.activeHostId
                    let nm = hostManager.networkManagers[profile.id]
                    let connected = nm?.isConnected ?? false
                    let connecting = nm?.connectionStatus.contains("CONNECTING") ?? false || nm?.connectionStatus.contains("STARTING") ?? false
                    let hostColor = Color(hex: profile.color) ?? .red

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hostManager.switchActiveHost(to: profile.id)
                        }
                    }) {
                        HStack(spacing: 4) {
                            // Per-host connection status dot
                            Circle()
                                .fill(connected ? Color.green : (connecting ? Color.orange : Color.secondary.opacity(0.5)))
                                .frame(width: 5, height: 5)
                            Text(profile.name.isEmpty ? profile.gatewayHost : profile.name)
                                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? .white : hostColor)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(isActive ? hostColor : Color.clear))
                        .overlay(Capsule().stroke(hostColor, lineWidth: isActive ? 0 : 1.5))
                    }
                    .buttonStyle(.plain)
                }

                // "+" Add Host button — always visible
                Button(action: { showingAddHost = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
        .sheet(isPresented: $showingAddHost) {
            AddHostSheet(hostManager: hostManager, isPresented: $showingAddHost, onHostAdded: onHostAdded)
        }
    }
}

// MARK: - No Host Empty State

struct NoHostEmptyStateView: View {
    var onAddHost: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.45))
            VStack(spacing: 4) {
                Text(l10n: "NO_HOST_TITLE")
                    .font(.system(size: 13, weight: .semibold))
                Text(l10n: "NO_HOST_SUBTITLE")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onAddHost) {
                Label(NSLocalizedString("NO_HOST_ADD_BUTTON", bundle: .clawsy, comment: ""), systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
    }
}

// MARK: - Add Host Sheet

struct AddHostSheet: View {
    @ObservedObject var hostManager: HostManager
    @Binding var isPresented: Bool
    var onHostAdded: ((HostProfile) -> Void)? = nil

    enum SetupMode { case choose, manual, agentAssist }
    enum AgentPhase { case prompt, waiting }

    @State private var setupMode: SetupMode = .choose
    @State private var agentPhase: AgentPhase = .prompt
    @State private var promptCopied = false

    // Manual form fields
    @State private var name = ""
    @State private var host = ""
    @State private var port = "18789"
    @State private var token = ""
    @State private var sshUser = ""
    @State private var useSshFallback = true
    @State private var selectedColor = HostProfile.defaultColors[1] // Blue default
    @State private var sharedFolderPath = ""

    private var canSave: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var installCommand: String {
        NSLocalizedString("ONBOARDING_INSTALL_PROMPT_FULL", bundle: .clawsy, comment: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(l10n: setupMode == .choose ? "ADD_HOST_TITLE" : (setupMode == .manual ? "ADD_HOST_TITLE" : "ADD_HOST_MODE_AGENT"))
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

            // Mode: Choose
            if setupMode == .choose {
                chooseView
            }

            // Mode: Agent Assist
            if setupMode == .agentAssist {
                agentAssistView
            }

            // Mode: Manual form
            if setupMode == .manual { ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Back link
                    Button(action: { setupMode = .choose }) {
                        Label(NSLocalizedString("ONBOARDING_INSTALL_BACK", bundle: .clawsy, comment: ""), systemImage: "chevron.left")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    // Name + Color
                    VStack(alignment: .leading, spacing: 8) {
                        Label(title: { Text(l10n: "HOST_IDENTITY") }, icon: { Image(systemName: "tag.fill") })
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.indigo)

                        TextField(text: $name) { Text(l10n: "HOST_NAME") }
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 6) {
                            Text(l10n: "HOST_COLOR")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 6) {
                                ForEach(HostProfile.defaultColors, id: \.self) { hex in
                                    let c = Color(hex: hex) ?? .red
                                    let sel = selectedColor == hex
                                    Circle().fill(c).frame(width: sel ? 18 : 13, height: sel ? 18 : 13)
                                        .overlay(Circle().stroke(Color.primary.opacity(sel ? 0.4 : 0), lineWidth: 1.5))
                                        .onTapGesture { selectedColor = hex }
                                        .animation(.easeInOut(duration: 0.1), value: sel)
                                }
                            }
                        }
                    }

                    Divider().opacity(0.3)

                    // Gateway
                    VStack(alignment: .leading, spacing: 8) {
                        Label(title: { Text(l10n: "GATEWAY") }, icon: { Image(systemName: "antenna.radiowaves.left.and.right") })
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)

                        HStack(spacing: 8) {
                            TextField(text: $host) { Text(l10n: "HOST") }
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            TextField(text: $port) { Text(l10n: "PORT") }
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 80)
                        }
                        SecureField(text: $token) { Text(l10n: "TOKEN") }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    Divider().opacity(0.3)

                    // SSH
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(title: { Text(l10n: "SSH_FALLBACK") }, icon: { Image(systemName: "lock.shield") })
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                            Spacer()
                            Toggle("", isOn: $useSshFallback).toggleStyle(.switch).scaleEffect(0.7)
                        }
                        TextField(text: $sshUser) { Text(l10n: "SSH_USER") }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .disabled(!useSshFallback)
                            .opacity(useSshFallback ? 1.0 : 0.5)
                    }
                }
                .padding(20)
            } // end ScrollView (manual)
            } // end if setupMode == .manual

            // Footer — only shown in manual mode
            if setupMode == .manual {
                Divider().opacity(0.3)
                HStack {
                    Button(NSLocalizedString("CANCEL", bundle: .clawsy, comment: "")) {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button(NSLocalizedString("ADD_HOST_SAVE", bundle: .clawsy, comment: "")) {
                        let safeName = name.trimmingCharacters(in: .whitespaces).isEmpty ? host : name
                        let profile = HostProfile(
                            name: safeName,
                            gatewayHost: host.trimmingCharacters(in: .whitespaces),
                            gatewayPort: port.isEmpty ? "18789" : port,
                            serverToken: token.trimmingCharacters(in: .whitespaces),
                            sshUser: sshUser,
                            useSshFallback: useSshFallback,
                            color: selectedColor,
                            sharedFolderPath: sharedFolderPath
                        )
                        hostManager.addHost(profile)
                        onHostAdded?(profile)
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 400)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }

    // MARK: - Sub-views

    @ViewBuilder private var chooseView: some View {
        VStack(spacing: 20) {
            Text(l10n: "ADD_HOST_MODE_TITLE")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.top, 8)
            HStack(spacing: 16) {
                modeButton(
                    icon: "key.fill", color: .blue,
                    title: NSLocalizedString("ADD_HOST_MODE_MANUAL", bundle: .clawsy, comment: ""),
                    desc: NSLocalizedString("ADD_HOST_MODE_MANUAL_DESC", bundle: .clawsy, comment: "")
                ) { setupMode = .manual }
                modeButton(
                    icon: "sparkles", color: .green,
                    title: NSLocalizedString("ADD_HOST_MODE_AGENT", bundle: .clawsy, comment: ""),
                    desc: NSLocalizedString("ADD_HOST_MODE_AGENT_DESC", bundle: .clawsy, comment: "")
                ) { setupMode = .agentAssist }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder private func modeButton(icon: String, color: Color, title: String, desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var agentAssistView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button(action: { setupMode = .choose }) {
                        Label(NSLocalizedString("ONBOARDING_INSTALL_BACK", bundle: .clawsy, comment: ""), systemImage: "chevron.left")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    if agentPhase == .prompt {
                        agentPromptContent
                    } else {
                        agentWaitingContent
                    }
                }
                .padding(20)
            }
            Divider().opacity(0.3)
            HStack {
                Button(NSLocalizedString("CANCEL", bundle: .clawsy, comment: "")) { isPresented = false }
                    .buttonStyle(.bordered)
                Spacer()
                if agentPhase == .waiting {
                    Button(NSLocalizedString("ONBOARDING_GATEWAY_HAVE_CODE", bundle: .clawsy, comment: "")) { setupMode = .manual }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder private var agentPromptContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n: "ONBOARDING_INSTALL_STEP1")
                .font(.system(size: 12, weight: .medium))
            Button(action: copyInstallCommand) {
                HStack(spacing: 8) {
                    Text(installCommand)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: promptCopied ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 11))
                        .foregroundColor(promptCopied ? .green : .secondary)
                }
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Text(l10n: "ONBOARDING_INSTALL_STEP2")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button(action: { agentPhase = .waiting }) {
                Label(NSLocalizedString("ONBOARDING_INSTALL_SENT", bundle: .clawsy, comment: ""), systemImage: "arrow.up.circle.fill")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    @ViewBuilder private var agentWaitingContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(l10n: "ONBOARDING_INSTALL_WAITING")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Text(l10n: "ONBOARDING_INSTALL_WAITING_HINT")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.vertical, 8)
    }

    private func copyInstallCommand() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(installCommand, forType: .string)
        promptCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { promptCopied = false }
    }
}
