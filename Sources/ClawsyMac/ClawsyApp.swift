import SwiftUI
import AppKit
import os
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

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var alertWindow: NSWindow?
    var quickSendWindow: NSWindow?
    var hudWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var hostManager: HostManager?

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

        let tintedLobster = lobster.copy() as! NSImage
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
        #if SCREENSHOT_MODE
        if CommandLine.arguments.contains("--screenshot") {
            ScreenshotRunner.run()
            return
        }
        #endif

        installClawsyDocumentation()
        SharedConfig.resolveBookmark()

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

        // Auto-Check for Updates
        UpdateManager.shared.checkForUpdates(silent: true)
        UpdateManager.shared.startPeriodicChecks()
        UpdateManager.shared.ensureNotificationPermission()

        // Redraw icon on appearance change
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func appearanceChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.updateMenuBarIcon() }
    }

    // MARK: - Hotkeys

    private func registerGlobalHotkeyMonitor() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.processHotkey(event: event)
        }
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
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
        guard let hm = hostManager, hm.isConnected, let poller = hm.activePoller else { return }
        if let content = ClipboardManager.getClipboardContent(),
           let jsonString = ClawsyEnvelopeBuilder.build(type: "clipboard", content: content) {
            poller.sendEnvelope(jsonString, sessionKey: poller.targetSessionKey)
            showStatusHUD(icon: "doc.on.clipboard.fill", title: "CLIPBOARD_SENT")
        }
    }

    private func handleGlobalScreenshot(interactive: Bool) {
        guard let hm = hostManager, hm.isConnected, let poller = hm.activePoller else { return }
        if popover.isShown { popover.performClose(nil) }
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.25)
            guard let b64 = ScreenshotManager.takeScreenshot(interactive: interactive) else {
                DispatchQueue.main.async { self.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "SCREENSHOT_FAILED") }
                return
            }
            if let jsonString = ClawsyEnvelopeBuilder.build(type: "screenshot", content: ["format": "jpeg", "base64": b64]) {
                poller.sendEnvelope(jsonString, sessionKey: poller.targetSessionKey)
            }
            DispatchQueue.main.async { self.showStatusHUD(icon: "camera.viewfinder", title: "SCREENSHOT_SENT") }
        }
    }

    private func handleGlobalCamera() {
        guard let hm = hostManager, hm.isConnected, let poller = hm.activePoller else { return }
        let camId   = SharedConfig.sharedDefaults.string(forKey: "activeCameraId") ?? ""
        let camName = SharedConfig.sharedDefaults.string(forKey: "activeCameraName") ?? "Camera"
        CameraManager.takePhoto(deviceId: camId.isEmpty ? nil : camId) { b64 in
            guard let b64 = b64 else {
                DispatchQueue.main.async { self.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "CAPTURE_FAILED") }
                return
            }
            if let jsonString = ClawsyEnvelopeBuilder.build(type: "camera", content: ["format": "jpeg", "base64": b64, "device": camName]) {
                poller.sendEnvelope(jsonString, sessionKey: poller.targetSessionKey)
            }
            DispatchQueue.main.async { self.showStatusHUD(icon: "camera.fill", title: "PHOTO_SENT") }
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
                    // Send directly as chat.send — no envelope wrapping needed
                    poller.sendMessage(text, sessionKey: poller.targetSessionKey)
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
        window.title = "Willkommen bei Clawsy"
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
