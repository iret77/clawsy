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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var clipboardWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create Status Bar Item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            button.image = NSImage(named: "Icon") // Use asset icon if available
            // Fallback if image load fails or is huge? Scale it? 
            // Better: Load specific size or system icon.
            // Let's stick to text 🦞 if image fails, or try to load "AppIcon" from assets
            if let iconImage = NSImage(named: "AppIcon") {
                iconImage.size = NSSize(width: 18, height: 18)
                button.image = iconImage
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
        
        let view = ClipboardPreviewWindow(
            content: content,
            onConfirm: {
                onConfirm()
                window.close()
            },
            onCancel: {
                onCancel()
                window.close()
            }
        )
        
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.clipboardWindow = window
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
