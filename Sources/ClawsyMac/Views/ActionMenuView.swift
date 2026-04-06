import SwiftUI
import ClawsyShared

/// Main action buttons: QuickSend, Screenshot, Clipboard, Camera.
///
/// Screenshot and Camera are never preemptively disabled in the UI.
/// Permissions (screen recording, camera) are checked at the point of use
/// — if missing, the system prompt is triggered or System Settings opened.
/// This matches the Apple HIG pattern: show items as available, handle
/// permission on demand.
struct ActionMenuView: View {
    @ObservedObject var hostManager: HostManager
    @EnvironmentObject var appDelegate: AppDelegate

    @State private var showingScreenshotMenu = false
    @State private var showingCameraMenu = false
    @State private var availableCameras: [[String: Any]] = []
    @AppStorage("activeCameraId", store: SharedConfig.sharedDefaults) private var activeCameraId = ""

    private var isConnected: Bool { hostManager.isConnected }

    var body: some View {
        VStack(spacing: 2) {
            // Quick Send
            Button(action: { appDelegate.showQuickSend() }) {
                MenuItemRow(icon: ClawsyTheme.Icons.quickSend, title: "QUICK_SEND",
                            isEnabled: isConnected,
                            shortcut: "⌘⇧\(SharedConfig.quickSendHotkey)")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            // Screenshot — permission checked in takeScreenshot()
            Button(action: { showingScreenshotMenu.toggle() }) {
                MenuItemRow(icon: ClawsyTheme.Icons.screenshot, title: "SCREENSHOT",
                            isEnabled: isConnected, hasChevron: true)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .popover(isPresented: $showingScreenshotMenu, arrowEdge: .trailing) {
                VStack(spacing: 0) {
                    Button(action: {
                        showingScreenshotMenu = false
                        takeScreenshot(interactive: false)
                    }) {
                        MenuItemRow(icon: "rectangle.dashed", title: "FULL_SCREEN",
                                    isEnabled: isConnected,
                                    shortcut: "⌘⇧\(SharedConfig.screenshotFullHotkey)")
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        showingScreenshotMenu = false
                        takeScreenshot(interactive: true)
                    }) {
                        MenuItemRow(icon: "plus.viewfinder", title: "INTERACTIVE_AREA",
                                    isEnabled: isConnected,
                                    shortcut: "⌘⇧\(SharedConfig.screenshotAreaHotkey)")
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .frame(width: 200)
            }

            // Clipboard
            Button(action: handleClipboardSend) {
                MenuItemRow(icon: ClawsyTheme.Icons.clipboard, title: "PUSH_CLIPBOARD",
                            isEnabled: isConnected,
                            shortcut: "⌘⇧\(SharedConfig.pushClipboardHotkey)")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            // Camera — permission checked in takePhoto()
            Button(action: {
                ensureCameraSelected()
                if !availableCameras.isEmpty { showingCameraMenu.toggle() }
            }) {
                MenuItemRow(icon: ClawsyTheme.Icons.camera, title: "CAMERA",
                            isEnabled: isConnected, hasChevron: true)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .popover(isPresented: $showingCameraMenu, arrowEdge: .trailing) {
                CameraMenuView(
                    cameras: availableCameras,
                    activeCameraId: $activeCameraId,
                    isConnected: isConnected,
                    onTakePhoto: { camId, camName in
                        showingCameraMenu = false
                        takePhoto(camId: camId, camName: camName)
                    }
                )
            }
        }
        .onAppear { loadCameras() }
    }

    // MARK: - Actions

    /// Close the main popover before running an operation that may trigger
    /// a system dialog (camera/screen recording permission).  macOS shows
    /// the dialog in a new window → app resigns active → `applicationWill-
    /// ResignActive` auto-closes the transient popover → the SwiftUI view
    /// hierarchy is destroyed → @EnvironmentObject references become
    /// invalid → crash in completion handlers.  Closing up-front avoids
    /// the race entirely.
    private func closePopover() {
        (NSApp.delegate as? AppDelegate)?.popover?.performClose(nil)
    }

    private func takeScreenshot(interactive: Bool) {
        guard let poller = hostManager.activePoller else { return }

        // Check screen recording permission before attempting capture.
        // If not granted, request it (macOS shows System Settings prompt).
        if !CGPreflightScreenCaptureAccess() {
            closePopover()
            CGRequestScreenCaptureAccess()
            return
        }

        closePopover()
        DispatchQueue.global(qos: .userInitiated).async {
            guard let b64 = ScreenshotManager.takeScreenshot(interactive: interactive) else {
                DispatchQueue.main.async {
                    (NSApp.delegate as? AppDelegate)?.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "SCREENSHOT_FAILED")
                }
                return
            }
            poller.sendEnvelope(type: "screenshot", content: ["format": "jpeg", "base64": b64])
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.showStatusHUD(icon: "camera.viewfinder", title: "SCREENSHOT_SENT")
            }
        }
    }

    private func handleClipboardSend() {
        guard let poller = hostManager.activePoller else { return }
        if let content = ClipboardManager.getClipboardContent() {
            poller.sendEnvelope(type: "clipboard", content: content)
            (NSApp.delegate as? AppDelegate)?.showStatusHUD(icon: "doc.on.clipboard.fill", title: "CLIPBOARD_SENT")
        }
    }

    private func takePhoto(camId: String, camName: String) {
        guard let poller = hostManager.activePoller else { return }

        // Close popover BEFORE CameraManager.takePhoto — the camera
        // permission dialog (.notDetermined on ad-hoc builds with fresh
        // TCC) would otherwise cause applicationWillResignActive to tear
        // down the view hierarchy while our completion handler still needs
        // to show a HUD.
        closePopover()

        CameraManager.takePhoto(deviceId: camId.isEmpty ? nil : camId) { b64 in
            guard let b64 = b64 else {
                DispatchQueue.main.async {
                    (NSApp.delegate as? AppDelegate)?.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "CAPTURE_FAILED")
                }
                return
            }
            poller.sendEnvelope(type: "camera", content: ["format": "jpeg", "base64": b64, "device": camName])
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.showStatusHUD(icon: "camera.fill", title: "PHOTO_SENT")
            }
        }
    }

    // MARK: - Camera Helpers

    private func loadCameras() {
        DispatchQueue.global(qos: .userInitiated).async {
            let cameras = CameraManager.listCameras()
            DispatchQueue.main.async {
                availableCameras = cameras
                ensureCameraSelected()
            }
        }
    }

    private func ensureCameraSelected() {
        let knownIds = availableCameras.compactMap { $0["id"] as? String }
        if activeCameraId.isEmpty || !knownIds.contains(activeCameraId) {
            if let first = availableCameras.first, let id = first["id"] as? String {
                activeCameraId = id
                SharedConfig.sharedDefaults.set(first["name"] as? String ?? "", forKey: "activeCameraName")
            }
        }
    }
}
