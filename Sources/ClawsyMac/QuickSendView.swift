import SwiftUI

struct QuickSendView: View {
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    var onSend: (String) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.accentColor)
                
                TextField(NSLocalizedString("QUICK_SEND_PLACEHOLDER", bundle: .clawsy, comment: ""), text: $text)
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
                        Image(systemName: "delete.left.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .help("Clear text")
                }
                
                Button(action: { onCancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
        }
        .frame(width: 450)
        .padding(20)
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            onCancel()
        }
    }
}
