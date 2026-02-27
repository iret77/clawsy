#if SCREENSHOT_MODE
import AppKit
import SwiftUI
import ClawsyShared

/// Runs only when built with -DSCREENSHOT_MODE.
/// Never compiled into production/release binaries.
enum ScreenshotRunner {

    static func run() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let outputDir = URL(fileURLWithPath: "docs/screenshots")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let shots: [(String, NSView)] = [
            ("01-popover",      makePopoverView()),
            ("02-settings",     makeSettingsView()),
            ("03-onboarding",   makeOnboardingView()),
            ("04-missioncontrol", makeMissionControlView()),
            ("05-filesync",     makeFileSyncView()),
            ("06-quicksend",    makeQuickSendView()),
        ]

        for (name, view) in shots {
            capture(view: view, name: name, into: outputDir)
        }

        print("✅ Screenshots saved to \(outputDir.path)")
        NSApp.terminate(nil)
    }

    // MARK: - Views with mock data

    private static func makePopoverView() -> NSView {
        let delegate = AppDelegate()
        let view = ContentView()
            .environmentObject(delegate)
        return sized(host(view), 240, 360)
    }

    private static func makeSettingsView() -> NSView {
        // SettingsView lives inside ContentView — render ContentView in settings-open state
        let delegate = AppDelegate()
        let view = ContentView().environmentObject(delegate)
        return sized(host(view), 420, 560)
    }

    private static func makeOnboardingView() -> NSView {
        var completed = false
        var presented = true
        let view = OnboardingView(
            isPresented: Binding(get: { presented }, set: { presented = $0 }),
            onboardingCompleted: Binding(get: { completed }, set: { completed = $0 })
        )
        return sized(host(view), 480, 460)
    }

    private static func makeMissionControlView() -> NSView {
        let store = TaskStore()
        store.tasks = [
            ClawsyTask(agentName: "CyberClaw",
                       title: "Clawsy bauen", progress: 0.72,
                       statusText: "Kompiliert Sources…",
                       model: "claude-sonnet-4-6",
                       startedAt: Date().addingTimeInterval(-180)),
            ClawsyTask(agentName: "CyberClaw",
                       title: "README aktualisieren", progress: 1.0,
                       statusText: "Fertig ✓",
                       model: "claude-sonnet-4-6",
                       startedAt: Date().addingTimeInterval(-60)),
        ]
        let view = MissionControlView(taskStore: store)
        return sized(host(view), 320, 400)
    }

    private static func makeFileSyncView() -> NSView {
        let view = FileSyncRequestWindow(
            filename: "report_2026.pdf",
            operation: "Upload",
            onConfirm: { _ in },
            onCancel: {}
        )
        return sized(host(view), 440, 260)
    }

    private static func makeQuickSendView() -> NSView {
        let view = QuickSendView(onSend: { _ in }, onCancel: {})
        return sized(host(view), 480, 120)
    }

    // MARK: - Capture

    private static func capture(view: NSView, name: String, into dir: URL) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: view.frame.size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Let the runloop render the view
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))

        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            print("⚠️  Could not capture \(name)")
            window.close()
            return
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = view.frame.size          // retina-correct logical size
        let png = rep.representation(using: .png, properties: [:])
        let dest = dir.appendingPathComponent("\(name).png")
        try? png?.write(to: dest)
        print("📸 \(dest.lastPathComponent)")
        window.close()
    }

    // MARK: - Helpers

    private static func host<V: View>(_ view: V) -> NSHostingView<V> {
        NSHostingView(rootView: view)
    }

    private static func sized(_ v: NSView, _ w: CGFloat, _ h: CGFloat) -> NSView {
        v.frame = NSRect(x: 0, y: 0, width: w, height: h)
        return v
    }
}
#endif
