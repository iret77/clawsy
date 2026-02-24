import SwiftUI

struct QuickSendView: View {
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    var onSend: (String) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Input Area
            HStack(spacing: 12) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor.opacity(0.8))
                
                TextField(NSLocalizedString("QUICK_SEND_PLACEHOLDER", bundle: .clawsy, comment: ""), text: $text)
                    .font(.system(size: 20, weight: .light))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        if !text.isEmpty {
                            onSend(text)
                            text = ""
                        }
                    }
                
                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            
            // Footer / Hints
            Divider()
                .opacity(0.3)
            
            HStack {
                Spacer()
                
                HStack(spacing: 16) {
                    Label(NSLocalizedString("SEND", bundle: .clawsy, comment: ""), systemImage: "return")
                    Label(NSLocalizedString("CANCEL", bundle: .clawsy, comment: ""), systemImage: "escape")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.05))
        }
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
        .frame(width: 600)
        .padding(40) // Padding for shadow
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            onCancel()
        }
    }
}
