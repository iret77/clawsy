import SwiftUI
import AppKit
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
    var networkManager: NetworkManager?
    var hostManager: HostManager?
    
    /// Updates the menu bar icon with a colored dot overlay for the active host
    func updateMenuBarIcon() {
        guard let button = statusBarItem?.button else { return }
        let iconName = NSImage.Name("Icon")
        guard let lobster = NSImage(named: iconName) else { return }
        lobster.isTemplate = true
        
        guard let activeProfile = hostManager?.activeProfile,
              let dotColor = NSColor(hex: activeProfile.color) else {
            // No active profile or single host — just use template icon
            button.image = lobster
            return
        }
        
        // Only show colored dot when there are multiple hosts
        guard let manager = hostManager, manager.profiles.count > 1 else {
            button.image = lobster
            return
        }
        
        // Composite: appearance-adaptive lobster + colored dot (bottom-right)
        // Cannot use isTemplate=true on composite (macOS would render dot monochrome),
        // so we tint the lobster manually based on current appearance.
        let size = lobster.size
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tintColor: NSColor = isDark ? .white : .black

        // Create tinted copy of lobster icon
        let tintedLobster = lobster.copy() as! NSImage
        tintedLobster.isTemplate = false
        tintedLobster.lockFocus()
        tintColor.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tintedLobster.unlockFocus()

        let composite = NSImage(size: size)
        composite.lockFocus()

        // Draw appearance-tinted lobster
        tintedLobster.draw(in: NSRect(origin: .zero, size: size))

        // Draw colored dot (6×6pt, bottom-right corner)
        let dotSize: CGFloat = 6
        let dotRect = NSRect(
            x: size.width - dotSize - 1,
            y: 1,
            width: dotSize,
            height: dotSize
        )
        dotColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        // White border for visibility
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
                let success = handleSetupCode(code)
                if success {
                    // Bring app to foreground and open onboarding if needed
                    NSApp.activate(ignoringOtherApps: true)
                    let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
                    if !onboardingCompleted {
                        openOnboardingWindowDirect()
                    }
                }
            }
        }
    }

    /// Decodes an OpenClaw setup code (base64 JSON: {url, token}) and configures a host profile.
    /// Returns true on success, false if the code is invalid.
    @discardableResult
    func handleSetupCode(_ raw: String) -> Bool {
        struct SetupPayload: Decodable {
            let url: String
            let token: String
        }
        // Fix base64 padding
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

        // Extract host + port from the URL (e.g. "wss://agenthost.ts.net" or "ws://127.0.0.1:18789")
        let (gatewayHost, gatewayPort) = Self.parseGatewayURL(payload.url)
        let profileName = gatewayHost.components(separatedBy: ".").first ?? gatewayHost

        let profile = HostProfile(
            name: profileName.isEmpty ? "OpenClaw" : profileName,
            gatewayHost: gatewayHost,
            gatewayPort: gatewayPort,
            serverToken: payload.token,
            useSshFallback: false   // setup code = direct WSS connection
        )

        // Bootstrap: inject pairing script + knowledge into the agent via HTTP
        // (happens before WS pairing — only needs the master token)
        Self.bootstrapAgentKnowledge(gatewayURL: payload.url, token: payload.token)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let hm = self.hostManager {
                // Replace an empty/unconfigured profile, or add as new
                let hasEmpty = hm.profiles.first(where: { $0.serverToken.isEmpty }) != nil
                if hasEmpty, let first = hm.profiles.first(where: { $0.serverToken.isEmpty }) {
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
                hm.connectAll { nm, p in
                    self.setupCallbacksForHost(nm: nm, profile: p)
                }
                self.networkManager = hm.activeNetworkManager
            }
            // Notify onboarding view that a setup code was imported
            NotificationCenter.default.post(
                name: NSNotification.Name("ClawsySetupCodeImported"),
                object: nil,
                userInfo: ["host": gatewayHost]
            )
        }
        return true
    }

    /// Bootstraps the OpenClaw server with the full Clawsy server stack.
    /// Called once after the setup code is decoded — needs only the master token (no WS pairing).
    ///
    /// What it does (all without sudo):
    ///   1. Downloads + installs the clawsy-bridge gateway plugin via `openclaw plugins install`
    ///   2. Downloads CLAWSY.md into the workspace (agent instructions + "pair clawsy" know-how)
    ///   3. Writes clawsy-pair.sh helper to workspace/tools/
    ///   4. Restarts the gateway so the plugin becomes active
    ///   5. Notifies the running agent session mid-session (no restart needed)
    static func bootstrapAgentKnowledge(gatewayURL: String, token: String) {
        let httpBase: String
        if let url = URL(string: gatewayURL) {
            let scheme = (url.scheme == "wss") ? "https" : "http"
            let host = url.host ?? "127.0.0.1"
            let port = url.port.map { ":\($0)" } ?? ""
            httpBase = "\(scheme)://\(host)\(port)"
        } else {
            httpBase = "http://127.0.0.1:18789"
        }
        guard let invokeURL = URL(string: "\(httpBase)/tools/invoke") else { return }
        let log = OSLog(subsystem: "ai.clawsy", category: "Bootstrap")

        func invoke(tool: String, args: [String: Any], label: String, completion: ((Bool) -> Void)? = nil) {
            var req = URLRequest(url: invokeURL)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 30
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["tool": tool, "args": args])
            URLSession.shared.dataTask(with: req) { data, _, err in
                if let err { os_log("Bootstrap %{public}@ error: %{public}@", log: log, type: .error, label, err.localizedDescription); return }
                let ok = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["ok"] as? Bool ?? false
                os_log("Bootstrap %{public}@: %{public}@", log: log, type: .info, label, ok ? "✅ OK" : "⚠️ FAILED")
                completion?(ok)
            }.resume()
        }

        // ── Step 1: Install clawsy-bridge plugin + CLAWSY.md + clawsy-pair.sh ──
        // Everything runs without sudo. openclaw plugins install handles plugin registration.
        let REPO = "https://raw.githubusercontent.com/iret77/clawsy/main"
        let serverSetupCommand = """
set -e
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
TOOLS="$WORKSPACE/tools"
PLUGIN_TMP="/tmp/clawsy-bridge-$$.ts"

echo "[clawsy-bootstrap] Starting server setup..."

# 1. Download + install gateway plugin (no sudo needed)
if ! openclaw plugins info clawsy-bridge 2>/dev/null | grep -q "enabled: true"; then
  curl -fsSL \(REPO)/server/clawsy-bridge.ts -o "$PLUGIN_TMP"
  openclaw plugins install "$PLUGIN_TMP"
  rm -f "$PLUGIN_TMP"
  echo "[clawsy-bootstrap] clawsy-bridge installed"
else
  echo "[clawsy-bootstrap] clawsy-bridge already installed"
fi

# 2. Install/update CLAWSY.md (agent instructions incl. 'pair clawsy')
mkdir -p "$WORKSPACE"
curl -fsSL \(REPO)/CLAWSY.md -o "$WORKSPACE/CLAWSY.md"
echo "[clawsy-bootstrap] CLAWSY.md installed"

# 3. Write clawsy-pair.sh (auto-approve pairing helper)
mkdir -p "$TOOLS"
curl -fsSL \(REPO)/tools/clawsy-pair.sh -o "$TOOLS/clawsy-pair.sh"
chmod +x "$TOOLS/clawsy-pair.sh"
echo "[clawsy-bootstrap] clawsy-pair.sh installed"

# 4. Restart gateway so plugin becomes active
openclaw gateway restart &
echo "[clawsy-bootstrap] Gateway restart triggered"
echo "[clawsy-bootstrap] Done."
"""
        invoke(tool: "exec", args: ["command": serverSetupCommand], label: "server-setup") { ok in
            guard ok else { return }
            // ── Step 2: Mid-session agent notification ──
            // The agent is already running — teach it about Clawsy without waiting for a restart.
            let msg = """
[Clawsy Bootstrap] Die macOS Companion App wurde soeben installiert. \
Clawsy-Bridge-Plugin, CLAWSY.md und clawsy-pair.sh wurden auf diesem Server eingerichtet. \
Wenn jemand "pair clawsy" schreibt: \
`CODE=$(bash ~/.openclaw/workspace/tools/clawsy-pair.sh --link-only | grep ^LINK= | cut -d= -f2-)` \
→ sende `clawsy://pair?code=$CODE` an den User \
→ starte `bash ~/.openclaw/workspace/tools/clawsy-pair.sh &` für Auto-Approve. \
Details in CLAWSY.md.
"""
            invoke(tool: "sessions_send", args: ["sessionKey": "main", "message": msg], label: "agent-notify")
        }
    }

    /// Parses a gateway URL string into (host, port) for HostProfile.
    /// Examples:
    ///   "wss://agenthost.ts.net"    → ("agenthost.ts.net", "443")
    ///   "ws://127.0.0.1:18789"      → ("127.0.0.1", "18789")
    ///   "agenthost"                 → ("agenthost", "18789")
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
        // Fallback: treat as plain hostname
        return (urlString, "18789")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Explicitly disconnect and kill SSH tunnel process for all hosts.
        // Without sandbox, child processes are no longer auto-killed on app exit.
        if let hm = hostManager {
            hm.disconnectAll()
        } else {
            networkManager?.disconnect()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if SCREENSHOT_MODE
        if CommandLine.arguments.contains("--screenshot") {
            ScreenshotRunner.run()
            return
        }
        #endif

        // Install CLAWSY.md into OpenClaw workspace on first launch (or if outdated)
        installClawsyDocumentation()

        // Resolve sandbox bookmark for Shared Folder early
        SharedConfig.resolveBookmark()
        
        // Kill any orphaned SSH tunnel process from a previous session holding port 18790
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/bin/sh")
        cleanup.arguments = ["-c", "lsof -ti tcp:18790 2>/dev/null | xargs kill -9 2>/dev/null; true"]
        cleanup.standardOutput = FileHandle.nullDevice
        cleanup.standardError = FileHandle.nullDevice
        try? cleanup.run()
        cleanup.waitUntilExit()
        
        // Single Instance Check
        let bundleID = Bundle.main.bundleIdentifier ?? "ai.clawsy"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        
        if runningApps.count > 1 {
            // Already running, try to bring the existing one to the front
            for app in runningApps {
                if app != NSRunningApplication.current {
                    app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                    break
                }
            }
            NSApp.terminate(nil)
            return
        }

        // Create Status Bar Item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            let iconName = NSImage.Name("Icon")
            if let menuIcon = NSImage(named: iconName) {
                // Remove hardcoded 18x18 size to allow asset-defined sizes
                menuIcon.isTemplate = true
                button.image = menuIcon
            } else {
                button.title = "Clawsy"
                print("Error: Menu Bar Icon 'Icon' not found in assets.")
            }
            button.action = #selector(togglePopover(_:))
        }
        
        // Create Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        // Inject AppDelegate into ContentView
        let contentView = ContentView().environmentObject(self)
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Register Global Hotkeys (local + global monitors)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.processHotkey(event: event) {
                return nil
            }
            return event
        }
        // Global monitor requires Accessibility permission — request it and register
        self.registerGlobalHotkeyMonitor()
        
        // Auto-Check for Updates (silent = background, shows notification if update found)
        UpdateManager.shared.checkForUpdates(silent: true)
        UpdateManager.shared.startPeriodicChecks()

        // Redraw menu bar icon when system appearance changes (Dark ↔ Light Mode)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        // Show onboarding on very first launch (before user ever clicks the menu bar icon)
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        if !onboardingCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.openOnboardingWindowDirect()
            }
        }
    }
    
    @objc private func appearanceChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateMenuBarIcon()
        }
    }

    private func registerGlobalHotkeyMonitor() {
        // Always register the monitor — it fires only when Accessibility is granted.
        // Do NOT auto-prompt on startup: macOS revokes permission on every binary update,
        // so prompting every launch is annoying. User can grant via Settings button instead.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.processHotkey(event: event)
        }
    }

    /// Call this when the user explicitly clicks "Grant Accessibility" in Settings.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func processHotkey(event: NSEvent) -> Bool {
        let required: NSEvent.ModifierFlags = [.command, .shift]
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(required) else { return false }
        let char = event.charactersIgnoringModifiers?.uppercased() ?? ""
        if char == SharedConfig.quickSendHotkey {
            self.showQuickSend()
            return true
        }
        if char == SharedConfig.pushClipboardHotkey {
            self.handleGlobalPushClipboard()
            return true
        }
        if char == SharedConfig.cameraHotkey {
            self.handleGlobalCamera()
            return true
        }
        if char == SharedConfig.screenshotFullHotkey {
            self.handleGlobalScreenshot(interactive: false)
            return true
        }
        if char == SharedConfig.screenshotAreaHotkey {
            self.handleGlobalScreenshot(interactive: true)
            return true
        }
        return false
    }
    
    private func handleGlobalPushClipboard() {
        guard let network = networkManager, network.isConnected else { return }
        if let content = ClipboardManager.getClipboardContent(),
           let jsonString = ClawsyEnvelopeBuilder.build(
                type: "clipboard",
                content: content,
                includeTelemetry: SharedConfig.extendedContextEnabled) {
            network.sendEvent(kind: "agent.request", payload: [
                "message": jsonString,
                "sessionKey": "clawsy-service",
                "deliver": false
            ])
            self.showStatusHUD(icon: "doc.on.clipboard.fill", title: "CLIPBOARD_SENT")
        }
    }
    
    private func handleGlobalScreenshot(interactive: Bool) {
        guard let network = networkManager, network.isConnected else { return }
        // Close popover if open so it doesn't appear in the screenshot
        if popover.isShown { popover.performClose(nil) }
        DispatchQueue.global(qos: .userInitiated).async {
            // Small delay to let the popover animation finish
            Thread.sleep(forTimeInterval: 0.25)
            guard let b64 = ScreenshotManager.takeScreenshot(interactive: interactive) else {
                DispatchQueue.main.async { self.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "SCREENSHOT_FAILED") }
                return
            }
            network.sendScreenshot(base64: b64)
            DispatchQueue.main.async { self.showStatusHUD(icon: "camera.viewfinder", title: "SCREENSHOT_SENT") }
        }
    }

    private func handleGlobalCamera() {
        guard let network = networkManager, network.isConnected else { return }
        let camId   = SharedConfig.sharedDefaults.string(forKey: "activeCameraId") ?? ""
        let camName = SharedConfig.sharedDefaults.string(forKey: "activeCameraName") ?? "Kamera"
        CameraManager.takePhoto(deviceId: camId.isEmpty ? nil : camId) { b64 in
            guard let b64 = b64 else {
                DispatchQueue.main.async { self.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "CAPTURE_FAILED") }
                return
            }
            network.sendPhoto(base64: b64, deviceName: camName)
            DispatchQueue.main.async { self.showStatusHUD(icon: "camera.fill", title: "PHOTO_SENT") }
        }
    }

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
            
            let hudView = StatusHUDView(icon: icon, title: title)
            window.contentView = NSHostingView(rootView: hudView)
            self.hudWindow = window
            
            window.orderFrontRegardless()
            
            // Auto-fade out
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
    
    func showQuickSend() {
        guard let network = networkManager, network.isConnected else { return }
        
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
                    if let jsonString = ClawsyEnvelopeBuilder.build(
                        type: "quick_send",
                        content: text,
                        includeTelemetry: SharedConfig.extendedContextEnabled) {
                        // Full envelope → clawsy-service (context storage)
                        network.sendDeeplink(message: jsonString, sessionKey: "clawsy-service")
                        // Trigger → main session (agent responds, quoting the message)
                        let trigger: [String: Any] = ["clawsy_envelope": [
                            "type": "quick_send_trigger",
                            "message": text
                        ]]
                        if let triggerData = try? JSONSerialization.data(withJSONObject: trigger),
                           let triggerString = String(data: triggerData, encoding: .utf8) {
                            network.sendDeeplink(message: triggerString, sessionKey: "main", deliver: true)
                        }
                    }
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
    
    func showClipboardRequest(content: String, direction: ClipboardDirection = .write, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let view = ClipboardPreviewWindow(
            content: content,
            direction: direction,
            onConfirm: { onConfirm(); self.alertWindow?.close() },
            onCancel: { onCancel(); self.alertWindow?.close() }
        )
        showFloatingWindow(view: view, title: "Clipboard Sync", autosaveName: "ai.clawsy.ClipboardWindow")
    }
    
    func showFileSyncRequest(filename: String, operation: String, onConfirm: @escaping (TimeInterval?) -> Void, onCancel: @escaping () -> Void) {
        let view = FileSyncRequestWindow(
            filename: filename,
            operation: operation,
            onConfirm: { duration in onConfirm(duration); self.alertWindow?.close() },
            onCancel: { onCancel(); self.alertWindow?.close() }
        )
        showFloatingWindow(view: view, title: NSLocalizedString("FILESYNC_WINDOW_TITLE", bundle: .clawsy, comment: ""), autosaveName: "ai.clawsy.FileWindow")
    }

    func showScreenshotRequest(requestedInteractive: Bool, onConfirm: @escaping (Bool) -> Void, onCancel: @escaping () -> Void) {
        let view = ScreenshotRequestWindow(
            requestedInteractive: requestedInteractive,
            onConfirm: { interactive in
                onConfirm(interactive)
                self.alertWindow?.close()
            },
            onCancel: {
                onCancel()
                self.alertWindow?.close()
            }
        )
        showFloatingWindow(view: view, title: "Screenshot Request", autosaveName: "ai.clawsy.ScreenshotWindow")
    }

    func showCameraPreview(image: NSImage, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let view = CameraPreviewView(
            image: image,
            onConfirm: { onConfirm(); self.alertWindow?.close() },
            onCancel: { onCancel(); self.alertWindow?.close() }
        )
        showFloatingWindow(view: view, title: "Camera Preview", autosaveName: "ai.clawsy.CameraWindow")
    }
    
    /// Called from ContentView (has SwiftUI binding)
    func openOnboardingWindow(onboardingCompleted: Binding<Bool>) {
        openOnboardingWindowInternal(onComplete: { onboardingCompleted.wrappedValue = true })
    }

    /// Called from AppDelegate on first launch (no SwiftUI binding available)
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
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Willkommen bei Clawsy"
        window.isReleasedWhenClosed = false
        window.center()

        let isPresented = Binding<Bool>(
            get: { window.isVisible },
            set: { newVal in
                if !newVal {
                    window.close()
                    self.onboardingWindow = nil
                }
            }
        )
        let onboardingCompleted = Binding<Bool>(
            get: { UserDefaults.standard.bool(forKey: "onboardingCompleted") },
            set: { newVal in
                if newVal { onComplete() }
            }
        )
        let isGatewayConnected = Binding<Bool>(
            get: { self.hostManager?.isConnected ?? false },
            set: { _ in }
        )
        let onImportSetupCode: (String) -> Bool = { [weak self] code in
            self?.handleSetupCode(code) ?? false
        }
        let serverSetupNeeded = Binding<Bool>(
            get: { self.networkManager?.serverSetupNeeded ?? false },
            set: { _ in }
        )
        let view = OnboardingView(
            isPresented: isPresented,
            onboardingCompleted: onboardingCompleted,
            isGatewayConnected: isGatewayConnected,
            serverSetupNeeded: serverSetupNeeded,
            onImportSetupCode: onImportSetupCode
        )
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusBarItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                // Ensure popover behaves like a standard menu (closes on outside clicks)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                
                // standard macOS behavior: popover should resign when other app/menu is clicked
                // .transient behavior usually handles this, aber explicit activation helps
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        // Close popover when user clicks away or switches apps
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    /// Copies CLAWSY.md from app bundle into the OpenClaw workspace so agents
    /// automatically have access to the documentation on first launch.
    private func installClawsyDocumentation() {
        guard let bundledDoc = Bundle.main.url(forResource: "CLAWSY", withExtension: "md") else { return }

        // Find OpenClaw workspace: ~/.openclaw/workspace/
        let home = FileManager.default.homeDirectoryForCurrentUser
        let workspace = home.appendingPathComponent(".openclaw/workspace")
        let destination = workspace.appendingPathComponent("CLAWSY.md")

        // Only copy if workspace exists
        guard FileManager.default.fileExists(atPath: workspace.path) else { return }

        // Copy if missing or if bundled version is newer (check by app version)
        let versionKey = "clawsy_doc_version_installed"
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let installedVersion = UserDefaults.standard.string(forKey: versionKey) ?? ""

        if !FileManager.default.fileExists(atPath: destination.path) || installedVersion != currentVersion {
            try? FileManager.default.copyItem(at: bundledDoc, to: destination)
            // Overwrite if exists
            if FileManager.default.fileExists(atPath: destination.path) && installedVersion != currentVersion {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.copyItem(at: bundledDoc, to: destination)
            }
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
        }
    }
}
