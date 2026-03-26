import SwiftUI
import ClawsyShared

struct DebugLogView: View {
    var logText: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n: "DEBUG_LOG_TITLE")
                        .font(.system(size: 15, weight: .semibold))
                    Text(SharedConfig.versionDisplay)
                        .font(ClawsyTheme.Font.footer)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider().clawsy()

            // Log Content
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
                .background(Color.black.opacity(0.03))
                .onChange(of: logText) { _ in
                    withAnimation { proxy.scrollTo("logEnd", anchor: .bottom) }
                }
            }

            Divider().clawsy()

            // Footer
            HStack {
                Text(l10n: "SELECT_TEXT_COPY")
                    .font(ClawsyTheme.Font.bannerBody)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }) {
                    Text(l10n: "COPY_ALL")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
}
