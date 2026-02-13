import SwiftUI
import AppKit

@main
struct ClawsyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            Text("Settings Window (Placeholder)")
                .frame(width: 300, height: 200)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var alertWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            if let appIcon = NSImage(named: "AppIcon") {
                appIcon.size = NSSize(width: 18, height: 18)
                appIcon.isTemplate = false
                button.image = appIcon
            } else {
                button.title = "🦞"
            }
            button.action = #selector(togglePopover(_:))
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 380)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(self))
    }
    
    private func showFloatingWindow(view: some View, title: String, autosaveName: String) {
        alertWindow?.close()
        
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
    
    func showClipboardRequest(content: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let view = ClipboardPreviewWindow(
            content: content,
            onConfirm: { onConfirm(); self.alertWindow?.close() },
            onCancel: { onCancel(); self.alertWindow?.close() }
        )
        showFloatingWindow(view: view, title: "Clipboard Sync", autosaveName: "ai.clawsy.ClipboardWindow")
    }
    
    func showFileSyncRequest(filename: String, operation: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let view = FileSyncRequestWindow(
            filename: filename,
            operation: operation,
            onConfirm: { onConfirm(); self.alertWindow?.close() },
            onCancel: { onCancel(); self.alertWindow?.close() }
        )
        showFloatingWindow(view: view, title: "File Sync", autosaveName: "ai.clawsy.FileWindow")
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusBarItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}
