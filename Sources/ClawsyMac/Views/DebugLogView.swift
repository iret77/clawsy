import SwiftUI
import ClawsyShared

struct DebugLogView: View {
    var logText: String

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            // Log Content — fills the window, title bar is handled by NSWindow
            ScrollViewReader { proxy in
                ScrollView {
                    if logText.isEmpty {
                        Text(l10n: "NO_DATA")
                            .font(ClawsyTheme.Font.code)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    } else {
                        Text(logText)
                            .font(ClawsyTheme.Font.code)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding()
                            .id("logEnd")
                    }
                }
                .scrollIndicators(.visible)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .onChange(of: logText) { _ in
                    withAnimation { proxy.scrollTo("logEnd", anchor: .bottom) }
                }
            }

            Divider().clawsy()

            // Footer — minimal, just copy action
            HStack {
                Text(SharedConfig.versionDisplay)
                    .font(ClawsyTheme.Font.footer)
                    .foregroundColor(.secondary.opacity(0.4))
                Spacer()
                Button(action: copyLog) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copied
                             ? NSLocalizedString("COPIED", bundle: .clawsy, comment: "")
                             : NSLocalizedString("COPY_ALL", bundle: .clawsy, comment: ""))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(logText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }

    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}
