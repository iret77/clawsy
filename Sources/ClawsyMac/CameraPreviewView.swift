import SwiftUI
import AVFoundation

struct CameraPreviewView: View {
    let image: NSImage
    let agentName: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var displayAgent: String {
        agentName ?? NSLocalizedString("GENERIC_AGENT", bundle: .clawsy, comment: "")
    }

    private var remoteUserText: String {
        if agentName != nil {
            return String(format: NSLocalizedString("REMOTE_NAMED_USER_ASKING", bundle: .clawsy, comment: ""), displayAgent)
        }
        return NSLocalizedString("REMOTE_USER_ASKING", bundle: .clawsy, comment: "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Area
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "camera.shutter.button.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .orange.opacity(0.3), radius: 4, y: 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("CAMERA_PREVIEW_TITLE")
                        .font(.system(size: 15, weight: .bold))
                    
                    Text(remoteUserText)
                        .font(ClawsyTheme.Font.headerHostName)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider().clawsy()

            // Content Area (Image Preview)
            VStack(spacing: 0) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 400, height: 250)
                    .clipped()
            }
            .background(Color.black.opacity(0.1))
            .frame(maxHeight: .infinity)
            
            Divider().clawsy()

            // Action Bar Footer
            HStack(spacing: 12) {
                Button("ALERT_DENY") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("SEND_TO_AGENT") {
                    onConfirm()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.03))
        }
        .frame(width: 400, height: 420)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClawsyTheme.Spacing.popoverCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ClawsyTheme.Spacing.popoverCornerRadius)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}
