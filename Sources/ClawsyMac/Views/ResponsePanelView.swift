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

// MARK: - Response Panel View

/// Displays an agent response in a macOS utility panel.
/// Text is fully selectable and copyable via NSTextView.
struct ResponsePanelView: View {
    let response: AgentResponse
    var onDismiss: () -> Void
    var onReply: ((String) -> Void)?

    @State private var replyText = ""
    @State private var isReplying = false
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Message body — selectable text
            SelectableText(response.message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)

            // Reply bar
            if onReply != nil {
                Divider()

                HStack(spacing: 8) {
                    if isReplying {
                        TextField(
                            NSLocalizedString("QUICK_SEND_PLACEHOLDER", bundle: .clawsy, comment: ""),
                            text: $replyText
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .focused($replyFocused)
                        .onSubmit(sendReply)

                        Button(action: { isReplying = false; replyText = "" }) {
                            Text(NSLocalizedString("CANCEL", bundle: .clawsy, comment: ""))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: {
                            isReplying = true
                            replyFocused = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 11))
                                Text(NSLocalizedString("RESPONSE_REPLY", bundle: .clawsy, comment: ""))
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: copyToClipboard) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                Text(NSLocalizedString("COPY_ALL", bundle: .clawsy, comment: ""))
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func sendReply() {
        guard !replyText.isEmpty else { return }
        onReply?(replyText)
        replyText = ""
        isReplying = false
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(response.message, forType: .string)
    }
}

// MARK: - Selectable Text (NSTextView wrapper)

/// NSTextView-backed text that supports native text selection and ⌘C.
struct SelectableText: NSViewRepresentable {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.allowsUndo = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
}
