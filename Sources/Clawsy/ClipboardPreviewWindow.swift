import SwiftUI
import AppKit

struct ClipboardPreviewWindow: View {
    let content: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    // Computed property for metadata
    private var charCount: Int {
        content.count
    }
    
    // Copy to system clipboard action
    private func copyToSystem() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Area
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 56, height: 56)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clipboard Request")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("\(charCount) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                Spacer()
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Content Area
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .lineSpacing(4)
                    .foregroundColor(.primary)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor))
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Action Bar
            HStack(spacing: 12) {
                Button(action: {
                    copyToSystem()
                }) {
                    Label("Copy Local", systemImage: "doc.on.doc")
                }
                .help("Copy to system clipboard without sending")
                
                Spacer()
                
                Button("Deny") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("Allow") {
                    onConfirm()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480, height: 380)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
    }
}

// Preview provider for development
struct ClipboardPreviewWindow_Previews: PreviewProvider {
    static var previews: some View {
        ClipboardPreviewWindow(
            content: "func hello() {\n    print(\"Hello World\")\n}",
            onConfirm: {},
            onCancel: {}
        )
    }
}
