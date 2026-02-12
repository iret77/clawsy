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
    var clipboardWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create Status Bar Item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            // Priority: Assets/Icon.png (if bundled), then AppIcon from assets, then Emoji 🦞
            if let iconImage = NSImage(named: "Icon") {
                iconImage.size = NSSize(width: 18, height: 18)
                iconImage.isTemplate = true
                button.image = iconImage
            } else if let appIcon = NSImage(named: "AppIcon") {
                appIcon.size = NSSize(width: 18, height: 18)
                appIcon.isTemplate = true
                button.image = appIcon
            } else {
                button.title = "🦞"
            }
            button.action = #selector(togglePopover(_:))
        }
        
        // Create Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 380)
        popover.behavior = .transient
        // Inject AppDelegate into ContentView so it can call showClipboardWindow
        popover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(self))
    }
    
    func showClipboardRequest(content: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        // Close previous if exists
        clipboardWindow?.close()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        
        window.center()
        window.setFrameAutosaveName("ClipboardRequestWindow")
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.title = "Clawsy Request"
        window.level = .floating // Force on top
        
        let view = ClipboardPreviewWindow(
            content: content,
            onConfirm: {
                print("DEBUG: Window confirmed")
                onConfirm()
                window.close()
                self.clipboardWindow = nil
            },
            onCancel: {
                print("DEBUG: Window cancelled")
                onCancel()
                window.close()
                self.clipboardWindow = nil
            }
        )
        
        window.contentView = NSHostingView(rootView: view)
        self.clipboardWindow = window // Retain BEFORE showing
        
        print("DEBUG: Showing Clipboard Window")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
