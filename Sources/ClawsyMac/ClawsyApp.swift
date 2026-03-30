import SwiftUI
import AppKit
import os
import UserNotifications
import ClawsyShared

@main
struct ClawsyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            VStack {
                Text(l10n: "SETTINGS_WINDOW_TITLE")
                let format = NSLocalizedString("VERSION_FORMAT %@", tableName: nil, bundle: .clawsy, value: "Clawsy %@", comment: "Version format string")
                Text(String(format: format, SharedConfig.versionDisplay))
            }
            .frame(width: 300, height: 200)
        }
    }
}

class QuickSendWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class HUDWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var alertWindow: NSWindow?
    var quickSendWindow: NSWindow?
    var responseWindow: NSWindow?
    var hudWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var addHostWindow: NSWindow?
    var settingsWindow: NSWindow?
    var debugLogWindow: NSWindow?
    var hostManager: HostManager? {
        didSet {
            guard let hostManager else { return }
            hostManager.onAgentResponse = { [weak self] agentName, message, sessionKey in
                let response = AgentResponse(
                    agentName: agentName,
                    message: message,
                    timestamp: Date(),
                    sessionKey: sessionKey
                )
                self?.showAgentResponse(response)
            }
        }
    }

    /// Pending responses keyed by notification identifier — opened on notification click
    private var pendingResponses: [String: AgentResponse] = [:]

    /// Last agent response — accessible from the main menu to re-show
    @Published var lastResponse: AgentResponse?

    // MARK: - Menu Bar Icon

    func updateMenuBarIcon() {
        guard let button = statusBarItem?.button else { return }
        let iconName = NSImage.Name("Icon")
        guard let lobster = NSImage(named: iconName) else { return }
        lobster.isTemplate = true

        guard let activeProfile = hostManager?.activeProfile,
              let dotColor = NSColor(hex: activeProfile.color),
              let manager = hostManager, manager.profiles.count > 1 else {
            button.image = lobster
            return
        }

        // Composite: appearance-adaptive lobster + colored dot (bottom-right)
        let size = lobster.size
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tintColor: NSColor = isDark ? .white : .black

        guard let tintedLobster = lobster.copy() as? NSImage else { return }
        tintedLobster.isTemplate = false
        tintedLobster.lockFocus()
        tintColor.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tintedLobster.unlockFocus()

        let composite = NSImage(size: size)
        composite.lockFocus()
        tintedLobster.draw(in: NSRect(origin: .zero, size: size))

        let dotSize: CGFloat = 6
        let dotRect = NSRect(x: size.width - dotSize - 1, y: 1, width: dotSize, height: dotSize)
        dotColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let borderPath = NSBezierPath(ovalIn: dotRect.insetBy(dx: 0.5, dy: 0.5))
        borderPath.lineWidth = 1.0
        borderPath.stroke()

        composite.unlockFocus()
        composite.isTemplate = false
        button.image = composite
    }

    // MARK: - URL Scheme Handler (clawsy://pair?code=BASE64)

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "clawsy" else { continue }
            if url.host == "pair",
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                if handleSetupCode(code) {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    @discardableResult
    func handleSetupCode(_ raw: String) -> Bool {
        struct SetupPayload: Decodable {
            let url: String
            let token: String
        }
        var base64 = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let rem = base64.count % 4
        if rem != 0 { base64 += String(repeating: "=", count: 4 - rem) }

        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(SetupPayload.self, from: data),
              !payload.url.isEmpty, !payload.token.isEmpty
        else {
            os_log("handleSetupCode: invalid setup code", log: OSLog(subsystem: "ai.clawsy", category: "Setup"), type: .error)
            return false
        }

        let (gatewayHost, gatewayPort) = Self.parseGatewayURL(payload.url)
        let profileName = gatewayHost.components(separatedBy: ".").first ?? gatewayHost

        let profile = HostProfile(
            name: profileName.isEmpty ? "OpenClaw" : profileName,
            gatewayHost: gatewayHost,
            gatewayPort: gatewayPort,
            serverToken: payload.token,
            useSshFallback: false
        )

        DispatchQueue.main.async { [weak self] in
            guard let self, let hm = self.hostManager else { return }
            if let first = hm.profiles.first(where: { $0.serverToken.isEmpty }) {
                hm.updateHost(HostProfile(
                    id: first.id, name: profile.name, gatewayHost: profile.gatewayHost,
                    gatewayPort: profile.gatewayPort, serverToken: profile.serverToken,
                    useSshFallback: false
                ))
                hm.switchActiveHost(to: first.id)
            } else {
                hm.addHost(profile)
                hm.switchActiveHost(to: profile.id)
            }
            hm.connectAll()

            NotificationCenter.default.post(
                name: NSNotification.Name("ClawsySetupCodeImported"),
                object: nil,
                userInfo: ["host": gatewayHost]
            )
        }
        return true
    }

    // Server bootstrap removed — Clawsy 1.0 uses Protocol V3 natively,
    // no server-side plugin installation needed.

    static func parseGatewayURL(_ urlString: String) -> (host: String, port: String) {
        if let url = URL(string: urlString), let host = url.host {
            let port: String
            if let p = url.port {
                port = String(p)
            } else {
                port = (url.scheme == "wss" || url.scheme == "https") ? "443" : "18789"
            }
            return (host, port)
        }
        return (urlString, "18789")
    }

    // MARK: - App Lifecycle

    func applicationWillTerminate(_ notification: Notification) {
        hostManager?.disconnectAll()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar app — no Dock icon
        NSApp.setActivationPolicy(.accessory)

        #if SCREENSHOT_MODE
        if CommandLine.arguments.contains("--screenshot") {
            ScreenshotRunner.run()
            return
        }
        #endif

        resetTCCIfSignatureChanged()
        installClawsyDocumentation()
        SharedConfig.resolveBookmark()

        // Listen for debug log open requests from settings
        NotificationCenter.default.addObserver(forName: .init("ai.clawsy.openDebugLog"), object: nil, queue: .main) { [weak self] _ in
            self?.openDebugLogWindow()
        }

        // Single Instance Check
        let bundleID = Bundle.main.bundleIdentifier ?? "ai.clawsy"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if runningApps.count > 1 {
            for app in runningApps where app != NSRunningApplication.current {
                app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                break
            }
            NSApp.terminate(nil)
            return
        }

        // Create Status Bar Item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem.button {
            let iconName = NSImage.Name("Icon")
            if let menuIcon = NSImage(named: iconName) {
                menuIcon.isTemplate = true
                button.image = menuIcon
            } else {
                button.title = "Clawsy"
            }
            button.action = #selector(togglePopover(_:))
        }

        // Create Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        let contentView = ContentView().environmentObject(self)
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Register Global Hotkeys
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.processHotkey(event: event) { return nil }
            return event
        }
        registerGlobalHotkeyMonitor()

        // Initial permission check — refreshes shared monitor so banners show immediately
        Task { @MainActor in PermissionMonitor.shared.refreshAll() }

        // Auto-Check for Updates
        UpdateManager.shared.checkForUpdates(silent: true)
        UpdateManager.shared.startPeriodicChecks()
        UpdateManager.shared.ensureNotificationPermission()

        // Notification categories + delegate for agent responses
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()

        // Redraw icon on appearance change
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        // Listen for Share Extension handoff
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handlePendingShare),
            name: Notification.Name("ai.clawsy.pendingShare"),
            object: nil
        )
    }

    @objc private func appearanceChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.updateMenuBarIcon() }
    }

    @objc private func handlePendingShare(_ notification: Notification) {
        guard let hm = hostManager, hm.isConnected, let poller = hm.activePoller else { return }
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConfig.appGroup
        ) else { return }

        let fileURL = container.appendingPathComponent("pending_share.json")
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [String: Any] else { return }

        // Send to clawsy-inbox via chat.send
        poller.sendEnvelope(type: "share", content: content)

        // Clean up
        try? FileManager.default.removeItem(at: fileURL)

        DispatchQueue.main.async {
            self.showStatusHUD(icon: "square.and.arrow.up", title: "SHARE_SUCCESS")
        }
    }

    // MARK: - Hotkeys

    private func registerGlobalHotkeyMonitor() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.processHotkey(event: event)
        }
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func processHotkey(event: NSEvent) -> Bool {
        let required: NSEvent.ModifierFlags = [.command, .shift]
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(required) else { return false }
        let char = event.charactersIgnoringModifiers?.uppercased() ?? ""
        switch char {
        case SharedConfig.quickSendHotkey:      showQuickSend(); return true
        case SharedConfig.pushClipboardHotkey:  handleGlobalPushClipboard(); return true
        case SharedConfig.cameraHotkey:         handleGlobalCamera(); return true
        case SharedConfig.screenshotFullHotkey:  handleGlobalScreenshot(interactive: false); return true
        case SharedConfig.screenshotAreaHotkey:  handleGlobalScreenshot(interactive: true); return true
        default: return false
        }
    }

    // MARK: - Global Actions (via Hotkey)

    private func handleGlobalPushClipboard() {
        guard let hm = hostManager, hm.isConnected, let poller = hm.activePoller else {
            logAction("Clipboard push skipped — not connected")
            return
        }
        if let content = ClipboardManager.getClipboardContent() {
            poller.sendEnvelope(type: "clipboard", content: content)
            logAction("Clipboard pushed (\(content.count) chars)")
            showStatusHUD(icon: "doc.on.clipboard.fill", title: "CLIPBOARD_SENT")
        }
    }

    private func handleGlobalScreenshot(interactive: Bool) {
        guard let hm = hostManager, hm.isConnected, let poller = hm.activePoller else {
            logAction("Screenshot skipped — not connected")
            return
        }

        // Check Screen Recording permission inline (no @MainActor dependency)
        if !Self.checkScreenRecordingPermission() {
            logAction("Screenshot skipped — Screen Recording permission missing")
            showStatusHUD(icon: "lock.shield", title: "PERM_MISSING_SCREENSHOT")
            DispatchQueue.main.async {
                PermissionMonitor.shared.openSettings(for: .screenRecording)
            }
            return
        }

        if popover.isShown { popover.performClose(nil) }
        logAction("Screenshot capturing (interactive: \(interactive))")
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.25)
            guard let b64 = ScreenshotManager.takeScreenshot(interactive: interactive) else {
                DispatchQueue.main.async {
                    self.logAction("Screenshot capture failed")
                    self.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "SCREENSHOT_FAILED")
                }
                return
            }
            poller.sendEnvelope(type: "screenshot", content: ["format": "jpeg", "base64": b64])
            DispatchQueue.main.async {
                self.logAction("Screenshot sent (\(b64.count / 1024)KB)")
                self.showStatusHUD(icon: "camera.viewfinder", title: "SCREENSHOT_SENT")
            }
        }
    }

    private func handleGlobalCamera() {
        guard let hm = hostManager, hm.isConnected, let poller = hm.activePoller else {
            logAction("Camera skipped — not connected")
            return
        }
        let camId   = SharedConfig.sharedDefaults.string(forKey: "activeCameraId") ?? ""
        let camName = SharedConfig.sharedDefaults.string(forKey: "activeCameraName") ?? "Camera"
        logAction("Camera capturing (\(camName))")
        CameraManager.takePhoto(deviceId: camId.isEmpty ? nil : camId) { b64 in
            guard let b64 = b64 else {
                DispatchQueue.main.async {
                    self.logAction("Camera capture failed")
                    self.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "CAPTURE_FAILED")
                }
                return
            }
            poller.sendEnvelope(type: "camera", content: ["format": "jpeg", "base64": b64, "device": camName])
            DispatchQueue.main.async {
                self.logAction("Photo sent from \(camName) (\(b64.count / 1024)KB)")
                self.showStatusHUD(icon: "camera.fill", title: "PHOTO_SENT")
            }
        }
    }

    // MARK: - Permission Check (nonisolated)

    /// Check Screen Recording without requiring @MainActor context.
    private static func checkScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    // MARK: - Debug Action Logging

    private func logAction(_ message: String) {
        guard let conn = hostManager?.activeConnection else { return }
        DispatchQueue.main.async {
            conn.rawLog += "\n[ACTION] \(message)"
        }
    }

    // MARK: - QuickSend

    func showQuickSend() {
        guard let hm = hostManager, hm.isConnected, let poller = hm.activePoller else { return }

        DispatchQueue.main.async {
            if self.quickSendWindow == nil {
                let window = QuickSendWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 600, height: 120),
                    styleMask: [.borderless, .fullSizeContentView],
                    backing: .buffered, defer: false)
                window.center()
                window.isReleasedWhenClosed = false
                window.isMovableByWindowBackground = true
                window.level = .floating
                window.backgroundColor = .clear
                window.isOpaque = false
                window.hasShadow = true

                let quickSendView = QuickSendView(onSend: { text in
                    self.logAction("QuickSend → \(poller.targetSessionKey): \(text.prefix(60))")
                    poller.sendChatMessage(text, sessionKey: poller.targetSessionKey)
                    self.hideQuickSend()
                }, onCancel: {
                    self.hideQuickSend()
                })

                window.contentView = NSHostingView(rootView: quickSendView)
                self.quickSendWindow = window
            }
            self.quickSendWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func hideQuickSend() {
        quickSendWindow?.orderOut(nil)
    }

    // MARK: - HUD

    func showStatusHUD(icon: String, title: String) {
        DispatchQueue.main.async {
            self.hudWindow?.close()
            let window = HUDWindow(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.backgroundColor = .clear
            window.hasShadow = true
            window.contentView = NSHostingView(rootView: StatusHUDView(icon: icon, title: title))
            self.hudWindow = window
            window.orderFrontRegardless()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    window.animator().alphaValue = 0
                } completionHandler: {
                    window.close()
                    self.hudWindow = nil
                }
            }
        }
    }

    // MARK: - Agent Response Toast

    func showAgentResponse(_ response: AgentResponse) {
        DispatchQueue.main.async {
            self.pendingResponses[response.id.uuidString] = response
            self.lastResponse = response
            self.showResponseToast(response)
            self.showResponseNotification(response)
            self.logAction("Agent response: \(response.agentName) (\(response.message.count) chars)")
        }
    }

    /// Shows a Clawsy-native response toast anchored to the menu bar status item.
    /// Styled like the main popover — vibrancy, ClawsyTheme, non-intrusive.
    func showResponseToast(_ response: AgentResponse) {
        responseWindow?.close()
        responseWindow = nil

        guard let button = statusBarItem?.button else { return }

        let toastView = ResponseToastView(
            response: response,
            onDismiss: { [weak self] in
                self?.dismissResponseToast()
            },
            onReply: { [weak self] replyText in
                guard let hm = self?.hostManager, let poller = hm.activePoller else { return }
                poller.sendChatMessage(replyText, sessionKey: response.sessionKey)
                self?.dismissResponseToast()
            },
            onCopy: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(response.message, forType: .string)
            }
        )

        let hostView = NSHostingView(rootView: toastView)
        hostView.setFrameSize(hostView.fittingSize)

        // Position below the status bar item (like the main popover)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostView.fittingSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .statusBar
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false  // Toast view has its own shadow
        window.contentView = hostView

        // Position in the notification area (top-right), below the menu bar
        if let screen = NSScreen.main {
            let padding: CGFloat = 12
            // visibleFrame excludes menu bar and dock — its maxY is the bottom of the menu bar
            let x = screen.frame.maxX - hostView.fittingSize.width - padding
            let y = screen.visibleFrame.maxY - hostView.fittingSize.height - padding
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let buttonWindow = button.window {
            let buttonFrame = button.convert(button.bounds, to: nil)
            let screenFrame = buttonWindow.convertToScreen(buttonFrame)
            let x = screenFrame.midX - hostView.fittingSize.width / 2
            let y = screenFrame.minY - hostView.fittingSize.height - 4
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }

        // Fade in
        window.alphaValue = 0
        self.responseWindow = window
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 1
        }

        // Auto-dismiss after 12 seconds (enough time to read)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            // Only auto-dismiss if still showing the same response
            guard self?.responseWindow === window else { return }
            self?.dismissResponseToast()
        }
    }

    private func dismissResponseToast() {
        guard let window = responseWindow else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            window.close()
            if self?.responseWindow === window {
                self?.responseWindow = nil
            }
        }
    }

    private func showResponseNotification(_ response: AgentResponse) {
        let content = UNMutableNotificationContent()
        content.title = response.agentName
        content.body = response.message.count > 200
            ? String(response.message.prefix(197)) + "…"
            : response.message
        // No sound — toast is the primary feedback; notification is silent history in Notification Center
        content.categoryIdentifier = "AGENT_RESPONSE"
        content.userInfo = [
            "agentName": response.agentName,
            "message": response.message,
            "sessionKey": response.sessionKey
        ]

        let request = UNNotificationRequest(
            identifier: response.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Notification goes to Notification Center only — no banner (toast is the primary UI).
    /// The entry stays in Notification Center so the user can find it later.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.list])
    }

    /// User clicked a notification — open the response panel
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let notificationId = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo

        // Try stored response first, fall back to userInfo
        if let agentResponse = pendingResponses.removeValue(forKey: notificationId) {
            showResponseToast(agentResponse)
        } else if let agentName = userInfo["agentName"] as? String,
                  let message = userInfo["message"] as? String,
                  let sessionKey = userInfo["sessionKey"] as? String {
            let agentResponse = AgentResponse(
                agentName: agentName,
                message: message,
                timestamp: Date(),
                sessionKey: sessionKey
            )
            showResponseToast(agentResponse)
        }

        completionHandler()
    }

    func setupNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_RESPONSE",
            title: NSLocalizedString("RESPONSE_VIEW", bundle: .clawsy, comment: ""),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "AGENT_RESPONSE",
            actions: [viewAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Permission Dialog Windows

    private func showFloatingWindow<V: View>(view: V, title: String, autosaveName: String) {
        DispatchQueue.main.async {
            self.alertWindow?.close()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.center()
            window.setFrameAutosaveName(autosaveName)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.title = title
            window.level = .floating
            window.contentView = NSHostingView(rootView: view)
            self.alertWindow = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showClipboardRequest(content: String, direction: ClipboardDirection = .write, agentName: String? = nil, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let view = ClipboardPreviewWindow(content: content, direction: direction, agentName: agentName,
            onConfirm: { onConfirm(); self.alertWindow?.close() },
            onCancel: { onCancel(); self.alertWindow?.close() })
        showFloatingWindow(view: view, title: "Clipboard Sync", autosaveName: "ai.clawsy.ClipboardWindow")
    }

    func showFileSyncRequest(filename: String, operation: String, agentName: String? = nil, onConfirm: @escaping (TimeInterval?) -> Void, onCancel: @escaping () -> Void) {
        let view = FileSyncRequestWindow(filename: filename, operation: operation, agentName: agentName,
            onConfirm: { duration in onConfirm(duration); self.alertWindow?.close() },
            onCancel: { onCancel(); self.alertWindow?.close() })
        showFloatingWindow(view: view, title: NSLocalizedString("FILESYNC_WINDOW_TITLE", bundle: .clawsy, comment: ""), autosaveName: "ai.clawsy.FileWindow")
    }

    func showScreenshotRequest(requestedInteractive: Bool, agentName: String? = nil, onConfirm: @escaping (Bool) -> Void, onCancel: @escaping () -> Void) {
        let view = ScreenshotRequestWindow(requestedInteractive: requestedInteractive, agentName: agentName,
            onConfirm: { interactive in onConfirm(interactive); self.alertWindow?.close() },
            onCancel: { onCancel(); self.alertWindow?.close() })
        showFloatingWindow(view: view, title: "Screenshot Request", autosaveName: "ai.clawsy.ScreenshotWindow")
    }

    func showCameraPreview(image: NSImage, agentName: String? = nil, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let view = CameraPreviewView(image: image, agentName: agentName,
            onConfirm: { onConfirm(); self.alertWindow?.close() },
            onCancel: { onCancel(); self.alertWindow?.close() })
        showFloatingWindow(view: view, title: "Camera Preview", autosaveName: "ai.clawsy.CameraWindow")
    }

    // MARK: - Onboarding

    func shouldShowOnboarding() -> Bool {
        let hasConfiguredHosts = hostManager?.profiles.contains(where: { !$0.serverToken.isEmpty }) ?? false
        if hasConfiguredHosts {
            UserDefaults.standard.set(true, forKey: "onboardingCompleted")
            return false
        }
        return !UserDefaults.standard.bool(forKey: "onboardingCompleted")
    }

    func openOnboardingWindow(onboardingCompleted: Binding<Bool>) {
        openOnboardingWindowInternal(onComplete: { onboardingCompleted.wrappedValue = true })
    }

    func openOnboardingWindowDirect() {
        openOnboardingWindowInternal(onComplete: {
            UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        })
    }

    private func openOnboardingWindowInternal(onComplete: @escaping () -> Void) {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = NSLocalizedString("ONBOARDING_WINDOW_TITLE", bundle: .clawsy, comment: "")
        window.isReleasedWhenClosed = false
        window.center()

        let isPresented = Binding<Bool>(
            get: { window.isVisible },
            set: { if !$0 { window.close(); self.onboardingWindow = nil } })
        let onboardingBinding = Binding<Bool>(
            get: { UserDefaults.standard.bool(forKey: "onboardingCompleted") },
            set: { if $0 { onComplete() } })
        let view = OnboardingView(
            isPresented: isPresented,
            onboardingCompleted: onboardingBinding,
            onImportSetupCode: { [weak self] code in self?.handleSetupCode(code) ?? false }
        )
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    // MARK: - Settings Window

    func openSettingsWindow() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let hm = hostManager else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = NSLocalizedString("SETTINGS_TITLE", bundle: .clawsy, comment: "")
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ai.clawsy.SettingsWindow")

        let isPresented = Binding<Bool>(
            get: { window.isVisible },
            set: { if !$0 { window.close(); self.settingsWindow = nil } })

        let view = SettingsTabView(hostManager: hm, isPresented: isPresented)
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func openDebugLogWindow() {
        if let existing = debugLogWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let hm = hostManager else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = NSLocalizedString("DEBUG_LOG", bundle: .clawsy, comment: "")
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ai.clawsy.DebugLogWindow")
        window.minSize = NSSize(width: 400, height: 250)

        let view = DebugLogView(logText: hm.rawLog)
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        debugLogWindow = window
    }

    // MARK: - Add Host Window

    func openAddHostWindow() {
        if let existing = addHostWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let hm = hostManager else { return }
        showAgentSetup(hostManager: hm)
    }

    private func showAgentSetup(hostManager hm: HostManager) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = NSLocalizedString("ADD_HOST_TITLE", bundle: .clawsy, comment: "")
        window.isReleasedWhenClosed = false
        window.center()

        let isPresented = Binding<Bool>(
            get: { window.isVisible },
            set: { if !$0 { window.close(); self.addHostWindow = nil } })

        let view = AgentSetupView(hostManager: hm, isPresented: isPresented, onShowManual: { [weak self] in
            window.close()
            self?.addHostWindow = nil
            self?.showManualAddHost(hostManager: hm)
        })
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        addHostWindow = window
    }

    private func showManualAddHost(hostManager hm: HostManager) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = NSLocalizedString("ADD_HOST_TITLE", bundle: .clawsy, comment: "")
        window.isReleasedWhenClosed = false
        window.center()

        let isPresented = Binding<Bool>(
            get: { window.isVisible },
            set: { if !$0 { window.close(); self.addHostWindow = nil } })

        let view = AddHostSheet(hostManager: hm, isPresented: isPresented, onHostAdded: { profile in
            hm.addHost(profile)
            hm.connectHost(profile.id)
        })
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        addHostWindow = window
    }

    // MARK: - Popover Toggle

    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusBarItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        if popover.isShown { popover.performClose(nil) }
    }

    // MARK: - TCC Reset on Signature Change (ad-hoc builds)

    /// Each ad-hoc build gets a new code signature. TCC binds permissions to
    /// signature+bundleID, so old entries become stale and `AXIsProcessTrusted()`
    /// returns false even though System Settings shows the toggle ON.
    /// Detect binary change via modification date and reset stale TCC entries.
    private func resetTCCIfSignatureChanged() {
        guard let executableURL = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              let modDate = attrs[.modificationDate] as? Date else { return }

        let currentStamp = String(Int(modDate.timeIntervalSince1970))
        let storedStamp = UserDefaults.standard.string(forKey: "lastBinaryStamp") ?? ""

        if !storedStamp.isEmpty && storedStamp != currentStamp {
            let bundleID = Bundle.main.bundleIdentifier ?? "ai.clawsy"
            for service in ["Accessibility", "ScreenCapture"] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                process.arguments = ["reset", service, bundleID]
                try? process.run()
                process.waitUntilExit()
            }
        }

        UserDefaults.standard.set(currentStamp, forKey: "lastBinaryStamp")
    }

    // MARK: - Documentation Install

    private func installClawsyDocumentation() {
        guard let bundledDoc = Bundle.main.url(forResource: "CLAWSY", withExtension: "md") else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let workspace = home.appendingPathComponent(".openclaw/workspace")
        let destination = workspace.appendingPathComponent("CLAWSY.md")
        guard FileManager.default.fileExists(atPath: workspace.path) else { return }

        let versionKey = "clawsy_doc_version_installed"
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let installedVersion = UserDefaults.standard.string(forKey: versionKey) ?? ""

        if !FileManager.default.fileExists(atPath: destination.path) || installedVersion != currentVersion {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: bundledDoc, to: destination)
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
        }
    }
}
