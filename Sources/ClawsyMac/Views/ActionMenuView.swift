import SwiftUI
import ClawsyShared

/// Main action buttons: QuickSend, Screenshot, Clipboard, Camera.
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
                MenuItemRow(icon: "paperplane.fill", title: "QUICK_SEND",
                            isEnabled: isConnected,
                            shortcut: "⌘⇧\(SharedConfig.quickSendHotkey)")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            // Screenshot
            Button(action: { showingScreenshotMenu.toggle() }) {
                MenuItemRow(icon: "camera", title: "SCREENSHOT", isEnabled: isConnected, hasChevron: true)
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
                MenuItemRow(icon: "doc.on.clipboard", title: "PUSH_CLIPBOARD",
                            isEnabled: isConnected,
                            shortcut: "⌘⇧\(SharedConfig.pushClipboardHotkey)")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            // Camera
            Button(action: {
                ensureCameraSelected()
                if !availableCameras.isEmpty { showingCameraMenu.toggle() }
            }) {
                MenuItemRow(icon: "video.fill", title: "CAMERA",
                            isEnabled: isConnected && !availableCameras.isEmpty, hasChevron: true)
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
            if let jsonString = ClawsyEnvelopeBuilder.build(type: "screenshot", content: ["format": "jpeg", "base64": b64]) {
                poller.sendEnvelope(jsonString, sessionKey: poller.targetSessionKey)
            }
            DispatchQueue.main.async { appDelegate.showStatusHUD(icon: "camera.viewfinder", title: "SCREENSHOT_SENT") }
        }
    }

    private func handleClipboardSend() {
        guard let poller = hostManager.activePoller else { return }
        if let content = ClipboardManager.getClipboardContent(),
           let jsonString = ClawsyEnvelopeBuilder.build(type: "clipboard", content: content) {
            poller.sendEnvelope(jsonString, sessionKey: poller.targetSessionKey)
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
            if let jsonString = ClawsyEnvelopeBuilder.build(type: "camera", content: ["format": "jpeg", "base64": b64, "device": camName]) {
                poller.sendEnvelope(jsonString, sessionKey: poller.targetSessionKey)
            }
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
