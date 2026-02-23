import SwiftUI
import AppKit

struct ScreenshotRequestWindow: View {
    let requestedInteractive: Bool
    let onConfirm: (Bool) -> Void // Bool = interactive
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Area
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCREENSHOT_REQUEST")
                            .font(.system(size: 15, weight: .semibold))
                        
                        Text("REMOTE_USER_ASKING")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                Divider().opacity(0.3)
                
                // Content Area
                VStack(spacing: 12) {
                    Text("SCREENSHOT_REQUEST_BODY")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    
                    // Mode Selection (if needed/desired, or just explain)
                    // We offer buttons for specific modes below
                }
                .frame(maxHeight: .infinity)
                
                Divider().opacity(0.3)
                
                // Action Bar
                HStack(spacing: 12) {
                    Button("DENY") {
                        onCancel()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(6)
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
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.1)) // Secondary action style
                    .cornerRadius(6)
                    
                    // Full Screen Option (Primary if requested, or always primary?)
                    Button(action: {
                        onConfirm(false)
                    }) {
                        Label("FULL_SCREEN", systemImage: "rectangle.dashed")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(20)
            }
        }
        .frame(width: 450, height: 220)
    }
}
