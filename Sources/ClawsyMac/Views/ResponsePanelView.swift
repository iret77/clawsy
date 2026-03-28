import SwiftUI
import ClawsyShared

// MARK: - Agent Response Model

struct AgentResponse: Identifiable {
    let id = UUID()
    let agentName: String
    let message: String
    let timestamp: Date
    let sessionKey: String

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Response Toast View

/// Clawsy-native agent response toast. Styled identically to the main popover —
/// vibrancy material, ClawsyTheme fonts, compact and non-intrusive.
/// Appears anchored to the menu bar item, not a random desktop window.
struct ResponseToastView: View {
    let response: AgentResponse
    var onDismiss: () -> Void
    var onReply: ((String) -> Void)?
    var onCopy: () -> Void

    @State private var replyText = ""
    @State private var isReplying = false
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)

                Text(response.agentName)
                    .font(ClawsyTheme.Font.formLabel)
                    .foregroundColor(.primary)

                Text(response.formattedTime)
                    .font(ClawsyTheme.Font.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Message body
            ScrollView {
                Text(response.message)
                    .font(.system(size: 12.5))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: 220)

            // Reply bar
            if onReply != nil {
                Divider().opacity(0.2).padding(.horizontal, 8)

                HStack(spacing: 6) {
                    if isReplying {
                        TextField(
                            NSLocalizedString("QUICK_SEND_PLACEHOLDER", bundle: .clawsy, comment: ""),
                            text: $replyText
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .focused($replyFocused)
                        .onSubmit(sendReply)

                        Button(action: { isReplying = false; replyText = "" }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: {
                            isReplying = true
                            replyFocused = true
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 10))
                                Text(NSLocalizedString("RESPONSE_REPLY", bundle: .clawsy, comment: ""))
                                    .font(ClawsyTheme.Font.caption)
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 300)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    private func sendReply() {
        guard !replyText.isEmpty else { return }
        onReply?(replyText)
        replyText = ""
        isReplying = false
    }
}
