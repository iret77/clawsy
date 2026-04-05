import SwiftUI
import UserNotifications
import CryptoKit
import CoreLocation
import ClawsyShared

struct ContentView: View {
    @StateObject private var hostManager = HostManager()
    @EnvironmentObject var appDelegate: AppDelegate
    @ObservedObject private var permissionMonitor = PermissionMonitor.shared

    @State private var showingMissionControl = false
    @State private var showingRuleEditor = false
    @State private var ruleEditorFolderPath: String = ""

    @State private var fileWatcher: FileWatcher?

    var body: some View {
        VStack(spacing: 0) {
            // ── Header: Title + Status + Connect Toggle ──
            // Matches Apple pattern: Bluetooth/WLAN title row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l10n: "APP_NAME")
                            .font(.system(size: 13, weight: .semibold))
                        if let profile = hostManager.activeProfile {
                            Text(profile.name.isEmpty ? profile.gatewayHost : profile.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: profile.color) ?? .secondary)
                        }
                    }
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .animation(ClawsyTheme.Animation.stateChange, value: hostManager.state)
                }
                Spacer()
                if !hostManager.profiles.isEmpty {
                    Toggle("", isOn: Binding(
                        get: { hostManager.isConnected },
                        set: { newValue in
                            guard let id = hostManager.activeHostId else { return }
                            if newValue { hostManager.connectHost(id) }
                            else { hostManager.disconnectHost(id) }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(isConnecting)
                }
            }
            .padding(.horizontal, ClawsyTheme.Spacing.contentH)
            .padding(.top, ClawsyTheme.Spacing.headerTop)
            .padding(.bottom, ClawsyTheme.Spacing.headerBottom)

            // ── Host Switcher — only with multiple hosts ──
            if hostManager.profiles.count > 1 {
                Divider().clawsy()
                HostSwitcherView(hostManager: hostManager, onHostAdded: { profile in
                    hostManager.addHost(profile)
                    hostManager.connectHost(profile.id)
                })
                .padding(.horizontal, ClawsyTheme.Spacing.contentH)
                .padding(.vertical, 6)
            }

            // ── Agent Picker — integrated, always accessible when connected ──
            if hostManager.isConnected {
                AgentPickerView(hostManager: hostManager)
            }

            // ── Pairing / Failure banners (critical only) ──
            if case .awaitingPairing = hostManager.state {
                bannerSection
                    .animation(ClawsyTheme.Animation.bannerSlide, value: hostManager.state)
            }
            if case .failed = hostManager.state {
                bannerSection
                    .animation(ClawsyTheme.Animation.bannerSlide, value: hostManager.state)
            }

            Divider().clawsy()

            // ── Empty state ──
            if hostManager.profiles.isEmpty {
                NoHostEmptyStateView(onAddHost: { appDelegate.openAddHostWindow() })
            }

            // ── Actions ──
            if !hostManager.profiles.isEmpty {
                VStack(spacing: 2) {
                    ActionMenuView(hostManager: hostManager)

                    // Last agent response
                    if let lastResponse = appDelegate.lastResponse {
                        LastResponseCard(response: lastResponse) {
                            appDelegate.showResponseToast(lastResponse)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)

                Divider().clawsy().padding(.vertical, 4).padding(.horizontal, 6)

                // ── Secondary actions ──
                VStack(spacing: 2) {
                    taskOverviewButton
                    settingsButton
                }
                .padding(.horizontal, 6)

                Divider().clawsy().padding(.vertical, 4).padding(.horizontal, 6)

                quitButton
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: ClawsyTheme.Spacing.popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
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
            permissionMonitor.register()

            ActionBridge.observe {
                if let action = ActionBridge.consumeAction() {
                    handleFinderSyncAction(action)
                }
            }
        }
        .onDisappear {
            permissionMonitor.unregister()
        }
        .onChange(of: hostManager.activeHostId) { _ in
            appDelegate.updateMenuBarIcon()
            setupFileWatcher()
        }
        .onChange(of: hostManager.isConnected) { _ in
            appDelegate.updateMenuBarIcon()
        }
        .sheet(isPresented: $showingRuleEditor) {
            RuleEditorView(folderPath: ruleEditorFolderPath, isPresented: $showingRuleEditor)
        }
    }

    // MARK: - Banner Section (critical states only — no permission nag)

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

    // MARK: - Connecting state helper (disables toggle during transitions)

    private var isConnecting: Bool {
        switch hostManager.state {
        case .connecting, .sshTunneling, .handshaking, .reconnecting: return true
        default: return false
        }
    }

    // MARK: - Status Text

    private var statusText: String {
        switch hostManager.state {
        case .disconnected:
            return NSLocalizedString("STATUS_DISCONNECTED", bundle: .clawsy, comment: "")
        case .connecting(let attempt):
            return String(format: NSLocalizedString("STATUS_CONNECTING %lld", bundle: .clawsy, comment: ""), attempt)
        case .sshTunneling:
            return NSLocalizedString("STATUS_STARTING_SSH", bundle: .clawsy, comment: "")
        case .handshaking:
            return NSLocalizedString("STATUS_HANDSHAKING", bundle: .clawsy, comment: "")
        case .awaitingPairing:
            return NSLocalizedString("STATUS_AWAITING_PAIR_APPROVE", bundle: .clawsy, comment: "")
        case .connected:
            return NSLocalizedString("STATUS_CONNECTED", bundle: .clawsy, comment: "")
        case .reconnecting(_, let seconds):
            return String(format: NSLocalizedString("STATUS_RECONNECT_COUNTDOWN %lld", bundle: .clawsy, comment: ""), seconds)
        case .failed(let failure):
            return failure.localizedTitle
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
        Button(action: { appDelegate.openSettingsWindow() }) {
            MenuItemRow(icon: ClawsyTheme.Icons.settings, title: "SETTINGS", isEnabled: true)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quit Button

    private var quitButton: some View {
        Button(action: { NSApplication.shared.terminate(nil) }) {
            MenuItemRow(icon: ClawsyTheme.Icons.quit, title: "QUIT", isEnabled: true)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Command Handler Registration

    private func registerCommandHandlers() {
        hostManager.onRegisterHandlers = { router, hostId in
            let profile = self.hostManager.profiles.first(where: { $0.id == hostId })
            let baseDir = profile?.sharedFolderPath ?? "~/Documents/Clawsy"
            let expandedBase = baseDir.replacingOccurrences(of: "~", with: NSHomeDirectory())

            // File commands (shared with node connection)
            Self.registerFileHandlers(on: router, expandedBase: expandedBase)

            // screen.capture
            router.register("screen.capture") { params, completion in
                Task { @MainActor in
                    // Check Screen Recording permission before attempting capture
                    let monitor = PermissionMonitor.shared
                    monitor.refreshAll()
                    if monitor.status[.screenRecording] != true {
                        Self.showPermissionAlert(
                            title: NSLocalizedString("PERM_ALERT_SCREEN_TITLE", bundle: .clawsy, comment: ""),
                            message: NSLocalizedString("PERM_ALERT_SCREEN_MESSAGE", bundle: .clawsy, comment: "")
                        ) {
                            monitor.openSettings(for: .screenRecording)
                        }
                        completion(.error(code: "permission_denied", message: "Screen Recording permission not granted"))
                        return
                    }
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
                    ["id": cam["id"] as? String ?? "",
                     "name": cam["name"] as? String ?? "Camera"] as [String: Any]
                }
                return .success(["cameras": list])
            }

            // location.get
            router.register("location.get") { _, completion in
                let locManager = LocationManager()
                locManager.requestPermission()
                locManager.startUpdating()

                // If we already have a cached location, return immediately
                if let loc = locManager.lastLocation {
                    locManager.stopUpdating()
                    completion(.success(Self.locationDict(from: loc)))
                    return
                }

                // Wait for first location update (with 10s timeout)
                var completed = false
                locManager.onLocationUpdate = { loc in
                    guard !completed else { return }
                    completed = true
                    locManager.stopUpdating()
                    completion(.success(Self.locationDict(from: loc)))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    guard !completed else { return }
                    completed = true
                    locManager.stopUpdating()
                    if let loc = locManager.lastLocation {
                        completion(.success(Self.locationDict(from: loc)))
                    } else {
                        completion(.error(code: "location_unavailable", message: "Could not get location within timeout"))
                    }
                }
            }
        }

        // Node connection: all handlers (gateway routes all node.invoke.request to node role)
        hostManager.onRegisterNodeHandlers = hostManager.onRegisterHandlers
    }

    private static func locationDict(from loc: ClawsyLocation) -> [String: Any] {
        var dict: [String: Any] = [
            "latitude": loc.latitude,
            "longitude": loc.longitude,
            "accuracy": loc.accuracy,
            "timestamp": loc.timestamp
        ]
        if let alt = loc.altitude { dict["altitude"] = alt }
        if let speed = loc.speed { dict["speed"] = speed }
        if let name = loc.name { dict["name"] = name }
        if let locality = loc.locality { dict["locality"] = locality }
        if let country = loc.country { dict["country"] = country }
        if let customName = loc.customName { dict["customName"] = customName }
        return dict
    }

    // MARK: - Permission Alert

    /// Show a macOS alert explaining how to grant a permission, then open Settings.
    private static func showPermissionAlert(title: String, message: String, onOpen: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("PERM_ALERT_OPEN_SETTINGS", bundle: .clawsy, comment: ""))
        alert.addButton(withTitle: NSLocalizedString("CANCEL", bundle: .clawsy, comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            onOpen()
        }
    }

    // MARK: - File Handler Registration (shared between operator and node)

    private static func registerFileHandlers(on router: CommandRouter, expandedBase: String) {
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

        // file.set — accept subPath / path / name as aliases for the target
        //            and content / base64 as aliases for the payload.
        router.registerSync("file.set") { params in
            guard let subPath = params["subPath"] as? String
                    ?? params["path"] as? String
                    ?? params["name"] as? String,
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

        // file.rename — rename a file (name only, same directory)
        router.registerSync("file.rename") { params in
            guard let path = params["path"] as? String ?? params["subPath"] as? String else {
                return .error(code: "missing_param", message: "path required")
            }
            guard let newName = params["newName"] as? String else {
                return .error(code: "missing_param", message: "newName required")
            }
            switch ClawsyFileManager.renameFile(baseDir: expandedBase, path: path, newName: newName) {
            case .success: return .success(["ok": true])
            case .failure(let err): return .error(code: "rename_failed", message: err.description)
            }
        }

        // file.rmdir — remove a directory (delegates to deleteFile which handles both files and dirs)
        router.registerSync("file.rmdir") { params in
            guard let subPath = params["subPath"] as? String ?? params["path"] as? String else {
                return .error(code: "missing_param", message: "subPath required")
            }
            switch ClawsyFileManager.deleteFile(baseDir: expandedBase, relativePath: subPath) {
            case .success: return .success(["ok": true])
            case .failure(let err): return .error(code: "rmdir_failed", message: err.description)
            }
        }

        // file.checksum — SHA256 checksum of a file
        router.registerSync("file.checksum") { params in
            guard let subPath = params["subPath"] as? String ?? params["path"] as? String else {
                return .error(code: "missing_param", message: "subPath required")
            }
            guard let fullPath = ClawsyFileManager.sandboxedPath(base: expandedBase, relativePath: subPath) else {
                return .error(code: "sandbox_violation", message: "Path escapes shared folder")
            }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) else {
                return .error(code: "read_failed", message: "Cannot read file")
            }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return .success(["checksum": hex, "algorithm": "sha256", "size": data.count])
        }

        // file.batch — execute multiple file operations sequentially
        router.registerSync("file.batch") { params in
            guard let ops = params["ops"] as? [[String: Any]], !ops.isEmpty else {
                return .error(code: "missing_param", message: "ops array required")
            }

            var results: [[String: Any]] = []
            for (index, op) in ops.enumerated() {
                guard let opType = op["op"] as? String else {
                    results.append(["index": index, "ok": false, "error": "missing 'op' field"])
                    continue
                }

                let result: CommandRouter.CommandResult
                switch opType {
                case "copy":
                    guard let source = op["source"] as? String, let dest = op["destination"] as? String else {
                        results.append(["index": index, "ok": false, "error": "copy requires source and destination"])
                        continue
                    }
                    switch ClawsyFileManager.copyFile(baseDir: expandedBase, source: source, destination: dest) {
                    case .success: result = .success(["ok": true])
                    case .failure(let err): result = .error(code: "copy_failed", message: err.description)
                    }
                case "move":
                    guard let source = op["source"] as? String, let dest = op["destination"] as? String else {
                        results.append(["index": index, "ok": false, "error": "move requires source and destination"])
                        continue
                    }
                    switch ClawsyFileManager.moveFile(baseDir: expandedBase, source: source, destination: dest) {
                    case .success: result = .success(["ok": true])
                    case .failure(let err): result = .error(code: "move_failed", message: err.description)
                    }
                case "delete":
                    guard let path = op["path"] as? String else {
                        results.append(["index": index, "ok": false, "error": "delete requires path"])
                        continue
                    }
                    switch ClawsyFileManager.deleteFile(baseDir: expandedBase, relativePath: path) {
                    case .success: result = .success(["ok": true])
                    case .failure(let err): result = .error(code: "delete_failed", message: err.description)
                    }
                case "mkdir":
                    guard let path = op["path"] as? String else {
                        results.append(["index": index, "ok": false, "error": "mkdir requires path"])
                        continue
                    }
                    switch ClawsyFileManager.createDirectory(baseDir: expandedBase, relativePath: path) {
                    case .success: result = .success(["ok": true])
                    case .failure(let err): result = .error(code: "mkdir_failed", message: err.description)
                    }
                case "rename":
                    guard let path = op["path"] as? String, let newName = op["newName"] as? String else {
                        results.append(["index": index, "ok": false, "error": "rename requires path and newName"])
                        continue
                    }
                    switch ClawsyFileManager.renameFile(baseDir: expandedBase, path: path, newName: newName) {
                    case .success: result = .success(["ok": true])
                    case .failure(let err): result = .error(code: "rename_failed", message: err.description)
                    }
                default:
                    results.append(["index": index, "ok": false, "error": "unknown op '\(opType)'"])
                    continue
                }

                switch result {
                case .success:
                    results.append(["index": index, "ok": true])
                case .error(_, let message):
                    results.append(["index": index, "ok": false, "error": message])
                }
            }

            let allOk = results.allSatisfy { $0["ok"] as? Bool == true }
            return .success(["ok": allOk, "results": results])
        }

        // file.get.chunk — read a specific chunk of a file (for large file downloads).
        //                  Accepts subPath/name/path aliases, and chunkIndex/index aliases.
        router.registerSync("file.get.chunk") { params in
            guard let subPath = params["subPath"] as? String ?? params["name"] as? String ?? params["path"] as? String else {
                return .error(code: "missing_param", message: "subPath required")
            }
            guard let chunkIndex = params["chunkIndex"] as? Int ?? params["index"] as? Int else {
                return .error(code: "missing_param", message: "chunkIndex required")
            }
            let chunkSize = params["chunkSizeBytes"] as? Int ?? params["chunkSize"] as? Int ?? 358400 // 350 KB default (safe under 512 KB WS limit)

            guard let fullPath = ClawsyFileManager.sandboxedPath(base: expandedBase, relativePath: subPath) else {
                return .error(code: "sandbox_violation", message: "Path escapes shared folder")
            }

            guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) else {
                return .error(code: "read_failed", message: "Cannot read file")
            }

            let totalBytes = data.count
            let totalChunks = max(1, Int(ceil(Double(totalBytes) / Double(chunkSize))))

            guard chunkIndex >= 0 && chunkIndex < totalChunks else {
                return .error(code: "invalid_chunk", message: "chunkIndex \(chunkIndex) out of range (0..<\(totalChunks))")
            }

            let start = chunkIndex * chunkSize
            let end = min(start + chunkSize, totalBytes)
            let chunk = data[start..<end]

            return .success([
                "content": chunk.base64EncodedString(),
                "chunkIndex": chunkIndex,
                "totalChunks": totalChunks,
                "totalBytes": totalBytes,
                "name": subPath
            ])
        }

        // file.set.chunk — write a chunk of a large file (assembled on last chunk).
        //                  Accepts subPath/name/path, chunk/content, chunkIndex/index,
        //                  totalChunks/total as aliases for backward compat with clients
        //                  that follow older SKILL.md versions.
        router.registerSync("file.set.chunk") { params in
            guard let subPath = params["subPath"] as? String ?? params["name"] as? String ?? params["path"] as? String else {
                return .error(code: "missing_param", message: "subPath required")
            }
            guard let chunkB64 = params["chunk"] as? String ?? params["content"] as? String else {
                return .error(code: "missing_param", message: "chunk (base64) required")
            }
            guard let chunkIndex = params["chunkIndex"] as? Int ?? params["index"] as? Int,
                  let totalChunks = params["totalChunks"] as? Int ?? params["total"] as? Int else {
                return .error(code: "missing_param", message: "chunkIndex and totalChunks required")
            }
            guard let chunkData = Data(base64Encoded: chunkB64) else {
                return .error(code: "invalid_base64", message: "Chunk content is not valid base64")
            }

            guard let basePath = ClawsyFileManager.sandboxedPath(base: expandedBase, relativePath: subPath) else {
                return .error(code: "sandbox_violation", message: "Path escapes shared folder")
            }

            // Write chunk to temp file
            let chunkPath = basePath + ".clawsy_chunk_\(chunkIndex)"
            do {
                let parent = URL(fileURLWithPath: chunkPath).deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try chunkData.write(to: URL(fileURLWithPath: chunkPath))
            } catch {
                return .error(code: "write_failed", message: "Failed to write chunk: \(error.localizedDescription)")
            }

            // Not the last chunk yet — acknowledge and wait
            if chunkIndex < totalChunks - 1 {
                return .success(["status": "chunk_received", "chunkIndex": chunkIndex])
            }

            // Last chunk — assemble all chunks into final file
            var assembled = Data()
            for i in 0..<totalChunks {
                let partPath = basePath + ".clawsy_chunk_\(i)"
                guard let partData = try? Data(contentsOf: URL(fileURLWithPath: partPath)) else {
                    // Clean up any written chunks
                    for j in 0..<totalChunks {
                        try? FileManager.default.removeItem(atPath: basePath + ".clawsy_chunk_\(j)")
                    }
                    return .error(code: "assembly_failed", message: "Missing chunk \(i) of \(totalChunks)")
                }
                assembled.append(partData)
            }

            // Write assembled file
            do {
                try assembled.write(to: URL(fileURLWithPath: basePath))
            } catch {
                // Clean up chunks
                for i in 0..<totalChunks {
                    try? FileManager.default.removeItem(atPath: basePath + ".clawsy_chunk_\(i)")
                }
                return .error(code: "write_failed", message: "Failed to write assembled file: \(error.localizedDescription)")
            }

            // Clean up chunk temp files
            for i in 0..<totalChunks {
                try? FileManager.default.removeItem(atPath: basePath + ".clawsy_chunk_\(i)")
            }

            return .success([
                "status": "ok",
                "name": subPath,
                "assembled": true,
                "size": assembled.count
            ])
        }
    }

    // MARK: - File Watcher

    private func setupFileWatcher() {
        fileWatcher?.stop()
        guard let profile = hostManager.activeProfile, !profile.sharedFolderPath.isEmpty else { return }
        let resolved = profile.sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        guard ClawsyFileManager.folderExists(at: resolved) else { return }

        // Ensure .clawsy manifests exist for root + all subfolders
        ClawsyManifestManager.provisionAll(in: resolved)

        let watcher = FileWatcher(url: URL(fileURLWithPath: resolved))
        watcher.typedCallback = { [weak hostManager] changedPath, eventType in
            guard let poller = hostManager?.activePoller else { return }
            if changedPath.hasSuffix(".agent_info.json") { return }
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
            ruleEditorFolderPath = action.folderPath
            showingRuleEditor = true
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

