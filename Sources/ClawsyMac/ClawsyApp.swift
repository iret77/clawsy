import SwiftUI
import AppKit
import ClawsyShared

@main
struct ClawsyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            VStack {
                Text(LocalizedStringKey("SETTINGS_WINDOW_TITLE"))
                Text("VERSION_FORMAT 0.2.0")
            }
            .frame(width: 300, height: 200)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var alertWindow: NSWindow?
    var quickSendWindow: NSWindow?
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
        
        // Register Global Hotkey (Option + Shift + C as a placeholder, or Cmd + Shift + K)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 40 { // Cmd + Shift + K
                self.showQuickSend()
                return nil
            }
            return event
        }
    }
    
    func showQuickSend() {
        guard let network = networkManager, network.isConnected else { return }
        
        DispatchQueue.main.async {
            if self.quickSendWindow == nil {
                let window = NSWindow(
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
                    network.sendEvent(kind: "quick_send", payload: ["text": text])
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
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}
