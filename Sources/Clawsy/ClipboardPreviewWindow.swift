import SwiftUI
import AppKit

struct ClipboardPreviewWindow: View {
    let content: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    private var charCount: Int {
        content.count
    }
    
    private func copyToSystem() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
    }
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Area
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLIPBOARD_SYNC")
                            .font(.system(size: 15, weight: .semibold))
                        
                        Text("CHAR_COUNT \(charCount)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                Divider().opacity(0.3)
                
                // Content Area
                ScrollView {
                    Text(content)
                        .font(.system(size: 12, design: .monospaced))
                        .lineSpacing(4)
                        .foregroundColor(.primary)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black.opacity(0.1))
                .frame(maxHeight: .infinity)
                
                Divider().opacity(0.3)
                
                // Action Bar
                HStack(spacing: 12) {
                    Button(action: {
                        copyToSystem()
                    }) {
                        Label("COPY_LOCAL", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("DENY") {
                        onCancel()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(6)
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Button("ALLOW") {
                        onConfirm()
                    }
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
        .frame(width: 500, height: 360)
    }
}
