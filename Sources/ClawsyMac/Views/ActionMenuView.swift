import SwiftUI
import ClawsyShared

/// Main action buttons: QuickSend, Screenshot, Clipboard, Camera.
struct ActionMenuView: View {
    @ObservedObject var hostManager: HostManager
    @ObservedObject private var permissionMonitor = PermissionMonitor.shared
    @EnvironmentObject var appDelegate: AppDelegate

    @State private var showingScreenshotMenu = false
    @State private var showingCameraMenu = false
    @State private var availableCameras: [[String: Any]] = []
    @AppStorage("activeCameraId", store: SharedConfig.sharedDefaults) private var activeCameraId = ""

    private var isConnected: Bool { hostManager.isConnected }
    private var hasScreenRecording: Bool { permissionMonitor.status[.screenRecording] == true }
    private var hasCamera: Bool { permissionMonitor.status[.camera] == true }

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

            // Screenshot
            Button(action: {
                if !hasScreenRecording {
                    permissionMonitor.openSettings(for: .screenRecording)
                } else {
                    showingScreenshotMenu.toggle()
                }
            }) {
                MenuItemRow(icon: ClawsyTheme.Icons.screenshot, title: "SCREENSHOT",
                            subtitle: !hasScreenRecording ? "ACTION_NEEDS_SCREEN_RECORDING" : nil,
                            isEnabled: isConnected && hasScreenRecording, hasChevron: hasScreenRecording)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .popover(isPresented: $showingScreenshotMenu, arrowEdge: .trailing) {
                VStack(spacing: 0) {
                    Button(action: {
                        showingScreenshotMenu = false
                        takeScreenshot(interactive: false)
                    }) {
                        MenuItemRow(icon: "rectangle.dashed", title: "FULL_SCREEN", isEnabled: isConnected,
                                    shortcut: "⌘⇧\(SharedConfig.screenshotFullHotkey)")
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        showingScreenshotMenu = false
                        takeScreenshot(interactive: true)
                    }) {
                        MenuItemRow(icon: "plus.viewfinder", title: "INTERACTIVE_AREA", isEnabled: isConnected,
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

            // Camera
            Button(action: {
                if !hasCamera {
                    permissionMonitor.openSettings(for: .camera)
                } else {
                    ensureCameraSelected()
                    if !availableCameras.isEmpty { showingCameraMenu.toggle() }
                }
            }) {
                MenuItemRow(icon: ClawsyTheme.Icons.camera, title: "CAMERA",
                            subtitle: !hasCamera ? "ACTION_NEEDS_CAMERA" : nil,
                            isEnabled: isConnected && hasCamera && !availableCameras.isEmpty,
                            hasChevron: hasCamera && !availableCameras.isEmpty)
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

    private func takeScreenshot(interactive: Bool) {
        guard let poller = hostManager.activePoller else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let b64 = ScreenshotManager.takeScreenshot(interactive: interactive) else {
                DispatchQueue.main.async { appDelegate.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "SCREENSHOT_FAILED") }
                return
            }
            poller.sendEnvelope(type: "screenshot", content: ["format": "jpeg", "base64": b64])
            DispatchQueue.main.async { appDelegate.showStatusHUD(icon: "camera.viewfinder", title: "SCREENSHOT_SENT") }
        }
    }

    private func handleClipboardSend() {
        guard let poller = hostManager.activePoller else { return }
        if let content = ClipboardManager.getClipboardContent() {
            poller.sendEnvelope(type: "clipboard", content: content)
            appDelegate.showStatusHUD(icon: "doc.on.clipboard.fill", title: "CLIPBOARD_SENT")
        }
    }

    private func takePhoto(camId: String, camName: String) {
        guard let poller = hostManager.activePoller else { return }
        CameraManager.takePhoto(deviceId: camId.isEmpty ? nil : camId) { b64 in
            guard let b64 = b64 else {
                DispatchQueue.main.async { appDelegate.showStatusHUD(icon: "exclamationmark.triangle.fill", title: "CAPTURE_FAILED") }
                return
            }
            poller.sendEnvelope(type: "camera", content: ["format": "jpeg", "base64": b64, "device": camName])
            DispatchQueue.main.async { appDelegate.showStatusHUD(icon: "camera.fill", title: "PHOTO_SENT") }
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
