import SwiftUI
import AppKit

struct ScreenshotRequestWindow: View {
    let requestedInteractive: Bool
    let agentName: String?
    let onConfirm: (Bool) -> Void // Bool = interactive
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
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .purple.opacity(0.3), radius: 4, y: 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("SCREENSHOT_REQUEST")
                        .font(.system(size: 15, weight: .bold))
                    
                    Text(remoteUserText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider().opacity(0.3)
            
            // Content Area
            VStack(spacing: 12) {
                Text("SCREENSHOT_REQUEST_BODY")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
            .frame(maxHeight: .infinity)
            
            Divider().opacity(0.3)
            
            // Action Bar Footer
            HStack(spacing: 12) {
                Button("DENY") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                // Interactive Option
                Button(action: {
                    onConfirm(true)
                }) {
                    Label("INTERACTIVE_AREA", systemImage: "plus.viewfinder")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.1)) // Secondary action style
                .cornerRadius(8)
                
                // Full Screen Option
                Button(action: {
                    onConfirm(false)
                }) {
                    Label("FULL_SCREEN", systemImage: "rectangle.dashed")
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
        .frame(width: 450, height: 240)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}
