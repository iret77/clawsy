import SwiftUI
import ClawsyShared

struct CameraMenuView: View {
    let cameras: [[String: Any]]
    @Binding var activeCameraId: String
    let isConnected: Bool
    let onTakePhoto: (String, String) -> Void

    private var activeCam: [String: Any]? {
        cameras.first { ($0["id"] as? String) == activeCameraId } ?? cameras.first
    }
    private var activeCamId: String   { activeCam?["id"]   as? String ?? "" }
    private var activeCamName: String { activeCam?["name"] as? String ?? "Camera" }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { onTakePhoto(activeCamId, activeCamName) }) {
                MenuItemRow(icon: "camera.fill", title: "TAKE_PHOTO", isEnabled: isConnected,
                            shortcut: "⌘⇧\(SharedConfig.cameraHotkey)")
            }
            .buttonStyle(.plain)

            Divider().padding(.vertical, 2).opacity(0.5)

            ForEach(cameras.indices, id: \.self) { idx in
                let cam = cameras[idx]
                let camId = cam["id"] as? String ?? ""
                let camName = cam["name"] as? String ?? "Camera \(idx + 1)"
                Button(action: {
                    activeCameraId = camId
                    SharedConfig.sharedDefaults.set(camName, forKey: "activeCameraName")
                }) {
                    MenuItemRow(
                        icon: camId == activeCameraId ? "checkmark.circle.fill" : "circle",
                        title: camName, isEnabled: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 220)
    }
}
