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

/// Displays an agent response in a professional macOS panel.
/// Text is fully selectable and copyable. Styled like a native macOS detail view.
struct ResponsePanelView: View {
    let response: AgentResponse
    var onDismiss: () -> Void
    var onReply: ((String) -> Void)?

    @State private var replyText = ""
    @State private var isReplying = false
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(response.agentName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(response.formattedTime)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Copy button
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("COPY_ALL", bundle: .clawsy, comment: ""))

                // Close button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            // Message body — selectable text
            ScrollView {
                SelectableText(response.message)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            // Reply bar (optional, shown on hover or click)
            if onReply != nil {
                Divider().opacity(0.3)

                HStack(spacing: 8) {
                    if isReplying {
                        TextField(
                            NSLocalizedString("QUICK_SEND_PLACEHOLDER", bundle: .clawsy, comment: ""),
                            text: $replyText
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($replyFocused)
                        .onSubmit {
                            if !replyText.isEmpty {
                                onReply?(replyText)
                                replyText = ""
                                isReplying = false
                            }
                        }

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
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 420, minHeight: 200, maxHeight: 500)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(response.message, forType: .string)
    }
}

// MARK: - Selectable Text (NSTextView wrapper)

/// NSTextView-backed text that supports native text selection, copy, and keyboard shortcuts.
/// SwiftUI's Text doesn't support selection. This is the macOS-native way.
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

        // Allow ⌘C, ⌘A
        textView.allowsUndo = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
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
