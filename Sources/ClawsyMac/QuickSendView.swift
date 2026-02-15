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
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                }
                
                Button(action: { onCancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
            )
            .shadow(radius: 10)
        }
        .frame(width: 400)
        .padding()
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            onCancel()
        }
    }
}
