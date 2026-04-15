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
    // NOTE: @EnvironmentObject var appDelegate was removed deliberately.
    // closePopover() destroys the NSPopover (and its SwiftUI environment)
    // synchronously.  If @EnvironmentObject is declared, any pending
    // body re-evaluation after the environment is gone causes a fatalError.
    // All AppDelegate access now goes through the NSApp.delegate singleton.

    @State private var showingScreenshotMenu = false
    @State private var showingCameraMenu = false
    @State private var availableCameras: [[String: Any]] = []
    @AppStorage("activeCameraId", store: SharedConfig.sharedDefaults) private var activeCameraId = ""

    private var isConnected: Bool { hostManager.isConnected }

    var body: some View {
        VStack(spacing: 2) {
            // Quick Send
            Button(action: { (NSApp.delegate as? AppDelegate)?.showQuickSend() }) {
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
                        // Don't set showingScreenshotMenu = false here — closePopover()
                        // in takeScreenshot destroys the entire hierarchy including this
                        // inner popover.  Setting @State then immediately destroying the
                        // view causes a SwiftUI re-render on a dead environment.
                        takeScreenshot(interactive: false)
                    }) {
                        MenuItemRow(icon: "rectangle.dashed", title: "FULL_SCREEN",
                                    isEnabled: isConnected,
                                    shortcut: "⌘⇧\(SharedConfig.screenshotFullHotkey)")
                    }
                    .buttonStyle(.plain)

                    Button(action: {
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
                        // Don't set showingCameraMenu = false — closePopover() in
                        // takePhoto destroys the entire hierarchy anyway.
                        takePhoto(camId: camId, camName: camName)
                    }
                )
            }
        }
        .onAppear { loadCameras() }
    }

    // MARK: - Actions
    //
    // Every action that may trigger a system dialog (camera permission,
    // screen recording Settings) MUST:
    //   1. NOT mutate @State before closing — avoids queued re-render on
    //      a dead SwiftUI environment.
    //   2. Dispatch the close + operation to the next run-loop tick so the
    //      button-action closure has returned and the current stack frame
    //      is clean before the popover (and view hierarchy) is destroyed.
    //   3. Resolve the poller fresh from AppDelegate at callback time —
    //      never capture view-owned references in escaping closures.

    private func takeScreenshot(interactive: Bool) {
        guard hostManager.activePoller != nil else { return }

        // Check screen recording permission before attempting capture.
        if !CGPreflightScreenCaptureAccess() {
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.popover?.performClose(nil)
                CGRequestScreenCaptureAccess()
            }
            return
        }

        // Dispatch to next run-loop tick so we leave the view's call stack
        // before the popover is destroyed.
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.popover?.performClose(nil)

            DispatchQueue.global(qos: .userInitiated).async {
                guard let b64 = ScreenshotManager.takeScreenshot(interactive: interactive) else {
                    DispatchQueue.main.async {
                        (NSApp.delegate as? AppDelegate)?.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "SCREENSHOT_FAILED")
                    }
                    return
                }
                DispatchQueue.main.async {
                    guard let poller = (NSApp.delegate as? AppDelegate)?.hostManager?.activePoller else { return }
                    poller.sendEnvelope(type: "screenshot", content: ["format": "jpeg", "base64": b64])
                    (NSApp.delegate as? AppDelegate)?.showStatusHUD(icon: "camera.viewfinder", title: "SCREENSHOT_SENT")
                }
            }
        }
    }

    private func handleClipboardSend() {
        guard let poller = (NSApp.delegate as? AppDelegate)?.hostManager?.activePoller else { return }
        if let content = ClipboardManager.getClipboardContent() {
            poller.sendEnvelope(type: "clipboard", content: content)
            (NSApp.delegate as? AppDelegate)?.showStatusHUD(icon: "doc.on.clipboard.fill", title: "CLIPBOARD_SENT")
        }
    }

    private func takePhoto(camId: String, camName: String) {
        guard hostManager.activePoller != nil else { return }

        // Dispatch to next run-loop tick: the button-action closure returns,
        // SwiftUI finishes its current update cycle, THEN we close the
        // popover and start the camera — no more tearing down the view
        // hierarchy from within its own call stack.
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.popover?.performClose(nil)

            CameraManager.takePhoto(deviceId: camId.isEmpty ? nil : camId) { b64 in
                guard let b64 = b64 else {
                    DispatchQueue.main.async {
                        (NSApp.delegate as? AppDelegate)?.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "CAPTURE_FAILED")
                    }
                    return
                }
                DispatchQueue.main.async {
                    guard let poller = (NSApp.delegate as? AppDelegate)?.hostManager?.activePoller else { return }
                    poller.sendEnvelope(type: "camera", content: ["format": "jpeg", "base64": b64, "device": camName])
                    (NSApp.delegate as? AppDelegate)?.showStatusHUD(icon: "camera.fill", title: "PHOTO_SENT")
                }
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
