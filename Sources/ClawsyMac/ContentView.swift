import SwiftUI
import UserNotifications
import ClawsyShared

struct ContentView: View {
    @StateObject private var hostManager = HostManager()
    @EnvironmentObject var appDelegate: AppDelegate

    @State private var showingSettings = false
    @State private var showingLog = false
    @State private var showingMissionControl = false
    @State private var showingAddHost = false

    @State private var fileWatcher: FileWatcher?

    var body: some View {
        VStack(spacing: 0) {
            // Host Switcher (only when multiple hosts)
            if hostManager.profiles.count > 1 {
                HostSwitcherView(hostManager: hostManager, onHostAdded: { profile in
                    hostManager.addHost(profile)
                    hostManager.connectHost(profile.id)
                })
                .padding(.horizontal, ClawsyTheme.Spacing.contentH)
                .padding(.top, 10)
                .padding(.bottom, 4)
                Divider().clawsy()
            }

            // Status Header
            StatusHeaderView(hostManager: hostManager)

            // Banners (animated)
            bannerSection
                .animation(ClawsyTheme.Animation.bannerSlide, value: hostManager.state)

            Divider().clawsy()

            // Empty state
            if hostManager.profiles.isEmpty {
                NoHostEmptyStateView(onAddHost: { showingAddHost = true })
                Divider().clawsy().padding(.horizontal, 6)
                quitButton
            }

            // Main content
            if !hostManager.profiles.isEmpty {
                AgentPickerView(hostManager: hostManager)

                VStack(spacing: 2) {
                    ActionMenuView(hostManager: hostManager)

                    Divider().clawsy().padding(.vertical, 4)

                    // Connect / Disconnect
                    connectButton

                    Divider().clawsy().padding(.vertical, 4)

                    // Task Overview
                    taskOverviewButton

                    // Settings
                    settingsButton

                    Divider().clawsy().padding(.vertical, 4)

                    quitButton
                }
                .padding(6)
            }
        }
        .frame(width: ClawsyTheme.Spacing.popoverWidth)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
        )
        .onAppear {
            appDelegate.hostManager = hostManager
            registerCommandHandlers()
            if !hostManager.profiles.isEmpty {
                hostManager.connectAll()
            }
            setupFileWatcher()
            appDelegate.updateMenuBarIcon()

            ActionBridge.observe {
                if let action = ActionBridge.consumeAction() {
                    handleFinderSyncAction(action)
                }
            }
        }
        .onChange(of: hostManager.activeHostId) { _ in
            appDelegate.updateMenuBarIcon()
            setupFileWatcher()
        }
        .onChange(of: hostManager.isConnected) { _ in
            appDelegate.updateMenuBarIcon()
        }
        .sheet(isPresented: $showingAddHost) {
            AddHostSheet(hostManager: hostManager, isPresented: $showingAddHost, onHostAdded: { profile in
                hostManager.addHost(profile)
                hostManager.connectHost(profile.id)
            })
        }
    }

    // MARK: - Banner Section

    @ViewBuilder
    private var bannerSection: some View {
        if case .awaitingPairing(let requestId) = hostManager.state {
            PairingApprovalBanner(requestId: requestId, copied: .constant(false))
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }

        if case .failed(let failure) = hostManager.state {
            ConnectionFailureBanner(failure: failure, onRetry: {
                if let id = hostManager.activeHostId { hostManager.connectHost(id) }
            }, onRepair: {
                hostManager.repairActiveConnection()
            })
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button(action: toggleConnection) {
            MenuItemRow(
                icon: connectButtonIcon,
                title: connectButtonTitle,
                color: connectButtonColor
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var connectButtonIcon: String {
        switch hostManager.state {
        case .connected: return ClawsyTheme.Icons.disconnect
        case .connecting, .sshTunneling, .handshaking, .reconnecting: return ClawsyTheme.Icons.reconnect
        case .awaitingPairing, .failed: return ClawsyTheme.Icons.reconnect
        case .disconnected: return ClawsyTheme.Icons.connect
        }
    }

    private var connectButtonTitle: String {
        switch hostManager.state {
        case .connected: return "DISCONNECT"
        case .awaitingPairing, .failed: return "RECONNECT"
        default: return "CONNECT"
        }
    }

    private var connectButtonColor: Color {
        switch hostManager.state {
        case .connected: return ClawsyTheme.Colors.failed
        case .awaitingPairing, .failed: return ClawsyTheme.Colors.connecting
        default: return .accentColor
        }
    }

    // MARK: - Task Overview Button

    private var taskOverviewButton: some View {
        Button(action: { showingMissionControl.toggle() }) {
            ZStack(alignment: .trailing) {
                MenuItemRow(icon: ClawsyTheme.Icons.taskOverview, title: "MISSION_CONTROL_TITLE", isEnabled: true)
                if let poller = hostManager.activePoller,
                   !poller.sessions.filter({ $0.status == "running" }).isEmpty {
                    Circle().fill(ClawsyTheme.Colors.connected)
                        .frame(width: 6, height: 6)
                        .padding(.trailing, ClawsyTheme.Spacing.contentH)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .popover(isPresented: $showingMissionControl, arrowEdge: .trailing) {
            MissionControlView(hostManager: hostManager)
        }
    }

    // MARK: - Settings Button

    private var settingsButton: some View {
        Button(action: { showingSettings.toggle() }) {
            MenuItemRow(icon: ClawsyTheme.Icons.settings, title: "SETTINGS", isEnabled: true)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .popover(isPresented: $showingSettings, arrowEdge: .trailing) {
            SettingsView(hostManager: hostManager, isPresented: $showingSettings,
                onShowDebugLog: {
                    showingSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { showingLog = true }
                },
                onHostAdded: { profile in
                    hostManager.addHost(profile)
                    hostManager.connectHost(profile.id)
                }
            )
            .frame(width: ClawsyTheme.Spacing.settingsWidth)
        }
        .background(
            Color.clear.popover(isPresented: $showingLog, arrowEdge: .trailing) {
                DebugLogView(logText: hostManager.rawLog, isPresented: $showingLog)
                    .frame(width: 400, height: 300)
            }
        )
    }

    // MARK: - Quit Button

    private var quitButton: some View {
        Button(action: { NSApplication.shared.terminate(nil) }) {
            MenuItemRow(icon: ClawsyTheme.Icons.quit, title: "QUIT", isEnabled: true)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    // MARK: - Connection Toggle

    private func toggleConnection() {
        guard let id = hostManager.activeHostId else { return }
        if hostManager.isConnected {
            hostManager.disconnectHost(id)
        } else {
            hostManager.connectHost(id)
        }
    }

    // MARK: - Command Handler Registration

    private func registerCommandHandlers() {
        hostManager.onRegisterHandlers = { router, hostId in
            let profile = self.hostManager.profiles.first(where: { $0.id == hostId })
            let baseDir = profile?.sharedFolderPath ?? "~/Documents/Clawsy"
            let expandedBase = baseDir.replacingOccurrences(of: "~", with: NSHomeDirectory())

            // file.list
            router.registerSync("file.list") { params in
                let subPath = params["subPath"] as? String ?? ""
                let recursive = params["recursive"] as? Bool ?? false
                let entries = ClawsyFileManager.listFiles(at: expandedBase, subPath: subPath, recursive: recursive)
                let list = entries.map { ["name": $0.name, "isDirectory": $0.isDirectory, "size": $0.size] as [String: Any] }
                return .success(["files": list])
            }

            // file.get
            router.registerSync("file.get") { params in
                guard let subPath = params["subPath"] as? String ?? params["path"] as? String else {
                    return .error(code: "missing_param", message: "subPath required")
                }
                switch ClawsyFileManager.readFile(baseDir: expandedBase, relativePath: subPath) {
                case .success(let b64): return .success(["base64": b64])
                case .failure(let err): return .error(code: "read_failed", message: err.description)
                }
            }

            // file.set
            router.registerSync("file.set") { params in
                guard let subPath = params["subPath"] as? String ?? params["path"] as? String,
                      let content = params["content"] as? String ?? params["base64"] as? String else {
                    return .error(code: "missing_param", message: "subPath and content required")
                }
                switch ClawsyFileManager.writeFile(baseDir: expandedBase, relativePath: subPath, base64Content: content) {
                case .success: return .success(["ok": true])
                case .failure(let err): return .error(code: "write_failed", message: err.description)
                }
            }

            // file.mkdir
            router.registerSync("file.mkdir") { params in
                guard let subPath = params["subPath"] as? String ?? params["path"] as? String else {
                    return .error(code: "missing_param", message: "subPath required")
                }
                switch ClawsyFileManager.createDirectory(baseDir: expandedBase, relativePath: subPath) {
                case .success: return .success(["ok": true])
                case .failure(let err): return .error(code: "mkdir_failed", message: err.description)
                }
            }

            // file.delete
            router.registerSync("file.delete") { params in
                guard let subPath = params["subPath"] as? String ?? params["path"] as? String else {
                    return .error(code: "missing_param", message: "subPath required")
                }
                switch ClawsyFileManager.deleteFile(baseDir: expandedBase, relativePath: subPath) {
                case .success: return .success(["ok": true])
                case .failure(let err): return .error(code: "delete_failed", message: err.description)
                }
            }

            // file.move
            router.registerSync("file.move") { params in
                guard let source = params["source"] as? String ?? params["from"] as? String,
                      let dest = params["destination"] as? String ?? params["to"] as? String else {
                    return .error(code: "missing_param", message: "source and destination required")
                }
                switch ClawsyFileManager.moveFile(baseDir: expandedBase, source: source, destination: dest) {
                case .success: return .success(["ok": true])
                case .failure(let err): return .error(code: "move_failed", message: err.description)
                }
            }

            // file.copy
            router.registerSync("file.copy") { params in
                guard let source = params["source"] as? String ?? params["from"] as? String,
                      let dest = params["destination"] as? String ?? params["to"] as? String else {
                    return .error(code: "missing_param", message: "source and destination required")
                }
                switch ClawsyFileManager.copyFile(baseDir: expandedBase, source: source, destination: dest) {
                case .success: return .success(["ok": true])
                case .failure(let err): return .error(code: "copy_failed", message: err.description)
                }
            }

            // file.stat
            router.registerSync("file.stat") { params in
                guard let subPath = params["subPath"] as? String ?? params["path"] as? String else {
                    return .error(code: "missing_param", message: "subPath required")
                }
                let stat = ClawsyFileManager.statFile(baseDir: expandedBase, relativePath: subPath)
                return .success(["exists": stat.exists, "isDirectory": stat.isDirectory,
                                 "size": stat.size as Any, "modified": stat.modified as Any])
            }

            // file.exists
            router.registerSync("file.exists") { params in
                guard let subPath = params["subPath"] as? String ?? params["path"] as? String else {
                    return .error(code: "missing_param", message: "subPath required")
                }
                let result = ClawsyFileManager.existsFile(baseDir: expandedBase, relativePath: subPath)
                return .success(["exists": result.exists, "isDirectory": result.isDirectory])
            }

            // screen.capture
            router.register("screen.capture") { params, completion in
                DispatchQueue.main.async {
                    let interactive = params["interactive"] as? Bool ?? false
                    self.appDelegate.showScreenshotRequest(
                        requestedInteractive: interactive,
                        onConfirm: { userInteractive in
                            if let b64 = ScreenshotManager.takeScreenshot(interactive: userInteractive) {
                                completion(.success(["format": "jpeg", "base64": b64]))
                            } else {
                                completion(.error(code: "capture_failed", message: "Screenshot failed"))
                            }
                        },
                        onCancel: {
                            completion(.error(code: "denied", message: "User denied screenshot"))
                        }
                    )
                }
            }

            // clipboard.read
            router.register("clipboard.read") { _, completion in
                DispatchQueue.main.async {
                    let content = ClipboardManager.getClipboardContent() ?? ""
                    self.appDelegate.showClipboardRequest(content: content, direction: .read,
                        onConfirm: {
                            if let current = ClipboardManager.getClipboardContent() {
                                completion(.success(["text": current]))
                            } else {
                                completion(.error(code: "empty", message: "Clipboard empty"))
                            }
                        },
                        onCancel: { completion(.error(code: "denied", message: "User denied clipboard read")) }
                    )
                }
            }

            // clipboard.write
            router.registerSync("clipboard.write") { params in
                guard let text = params["text"] as? String ?? params["content"] as? String else {
                    return .error(code: "missing_param", message: "text required")
                }
                ClipboardManager.setClipboardContent(text)
                return .success(["ok": true])
            }

            // camera.snap
            router.register("camera.snap") { params, completion in
                let camId = params["deviceId"] as? String
                CameraManager.takePhoto(deviceId: camId) { b64 in
                    if let b64 = b64 {
                        completion(.success(["format": "jpeg", "base64": b64]))
                    } else {
                        completion(.error(code: "capture_failed", message: "Camera capture failed"))
                    }
                }
            }

            // camera.list
            router.registerSync("camera.list") { _ in
                let cameras = CameraManager.listCameras()
                let list = cameras.map { cam in
                    ["id": cam["uniqueID"] as? String ?? "",
                     "name": cam["localizedName"] as? String ?? "Camera"] as [String: Any]
                }
                return .success(["cameras": list])
            }
        }
    }

    // MARK: - File Watcher

    private func setupFileWatcher() {
        fileWatcher?.stop()
        guard let profile = hostManager.activeProfile, !profile.sharedFolderPath.isEmpty else { return }
        let resolved = profile.sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        guard ClawsyFileManager.folderExists(at: resolved) else { return }

        let watcher = FileWatcher(url: URL(fileURLWithPath: resolved))
        watcher.typedCallback = { [weak hostManager] changedPath, eventType in
            guard let poller = hostManager?.activePoller else { return }
            if changedPath.hasSuffix(".agent_status.json") || changedPath.hasSuffix(".agent_info.json") { return }
            let relativePath = changedPath.replacingOccurrences(of: resolved, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let triggerName = eventType.rawValue

            let changedURL = URL(fileURLWithPath: changedPath)
            let fileName = changedURL.lastPathComponent
            let parentFolder = changedURL.deletingLastPathComponent().path

            if !fileName.hasPrefix(".") {
                let matchedRules = ClawsyManifestManager.matchingRules(for: fileName, in: parentFolder, trigger: triggerName)
                for rule in matchedRules {
                    if rule.action == "send_to_agent" {
                        poller.sendEnvelope(type: "file.rule_triggered", content: [
                            "trigger": triggerName, "fileName": fileName,
                            "relativePath": relativePath, "ruleId": rule.id, "prompt": rule.prompt
                        ] as [String: Any])
                    } else if rule.action == "notify" {
                        DispatchQueue.main.async {
                            let content = UNMutableNotificationContent()
                            content.title = NSLocalizedString("RULE_NOTIFY_TITLE", bundle: .clawsy, comment: "")
                            content.body = rule.prompt.isEmpty ? fileName : "\(rule.prompt): \(fileName)"
                            content.sound = .default
                            UNUserNotificationCenter.current().add(
                                UNNotificationRequest(identifier: "rule-\(rule.id)-\(UUID().uuidString.prefix(8))", content: content, trigger: nil))
                        }
                    }
                }
            }
        }
        watcher.start()
        self.fileWatcher = watcher
    }

    // MARK: - FinderSync

    private func handleFinderSyncAction(_ action: PendingAction) {
        guard let poller = hostManager.activePoller else { return }
        switch action.kind {
        case "open_rule_editor":
            break // TODO: RuleEditorView sheet
        case "run_actions":
            let folderURL = URL(fileURLWithPath: action.folderPath)
            let files = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
            for fileURL in files where !fileURL.lastPathComponent.hasPrefix(".") {
                let fileName = fileURL.lastPathComponent
                let rules = ClawsyManifestManager.matchingRules(for: fileName, in: action.folderPath, trigger: "manual")
                for rule in rules where rule.action == "send_to_agent" {
                    poller.sendEnvelope(type: "file.rule_triggered", content: [
                        "trigger": "manual", "fileName": fileName, "ruleId": rule.id, "prompt": rule.prompt
                    ] as [String: Any])
                }
            }
        default:
            break
        }
    }
}
