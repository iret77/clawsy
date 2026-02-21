import SwiftUI
import AppKit
import ClawsyShared

@main
struct ClawsyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            VStack {
                Text("SETTINGS_WINDOW_TITLE", bundle: .clawsy)
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
    var networkManager: NetworkManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        popover.contentSize = NSSize(width: 240, height: 360)
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
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = self.processHotkey(event: event)
        }
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
                    contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                    styleMask: [.borderless, .fullSizeContentView],
                    backing: .buffered, defer: false)
                
                window.center()
                window.isReleasedWhenClosed = false
                window.isMovableByWindowBackground = true
                window.level = .floating
                window.backgroundColor = .clear
                window.hasShadow = true
                
                let quickSendView = QuickSendView(onSend: { text in
                    if let jsonString = ClawsyEnvelopeBuilder.build(
                        type: "quick_send",
                        content: text,
                        includeTelemetry: SharedConfig.extendedContextEnabled) {
                        network.sendEvent(kind: "agent.request", payload: [
                            "message": jsonString,
                            "sessionKey": "main",
                            "deliver": true,
                            "receipt": false
                        ])
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
    
    func showClipboardRequest(content: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let view = ClipboardPreviewWindow(
            content: content,
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
        showFloatingWindow(view: view, title: "File Sync", autosaveName: "ai.clawsy.FileWindow")
    }

    func showCameraPreview(image: NSImage, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let view = CameraPreviewView(
            image: image,
            onConfirm: { onConfirm(); self.alertWindow?.close() },
            onCancel: { onCancel(); self.alertWindow?.close() }
        )
        showFloatingWindow(view: view, title: "Camera Preview", autosaveName: "ai.clawsy.CameraWindow")
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
}
