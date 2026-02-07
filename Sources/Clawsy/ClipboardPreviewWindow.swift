import SwiftUI

struct ClipboardPreviewWindow: View {
    let content: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .padding(.top, 20)
            
            // Title
            Text("Clipboard Request")
                .font(.title2)
                .fontWeight(.bold)
            
            // Content Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Content:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal)
            
            // Actions
            HStack(spacing: 12) {
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
            .padding(.bottom, 20)
        }
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .frame(width: 400, height: 300)
    }
}
