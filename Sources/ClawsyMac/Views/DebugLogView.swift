import SwiftUI
import ClawsyShared

struct DebugLogView: View {
    var logText: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n: "DEBUG_LOG_TITLE")
                        .font(.system(size: 15, weight: .bold))
                    Text(SharedConfig.versionDisplay)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().opacity(0.3)

            ScrollView {
                if logText.isEmpty {
                    Text(l10n: "NO_DATA")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                } else {
                    Text(logText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
            .scrollIndicators(.visible)
            .background(Color.black.opacity(0.05))

            Divider().opacity(0.3)

            HStack {
                Text(l10n: "SELECT_TEXT_COPY")
                    .font(.system(size: 11))
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
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.02))
        }
    }
}
