import SwiftUI
import ClawsyShared

struct PairingApprovalBanner: View {
    let requestId: String
    @Binding var copied: Bool

    private var command: String { "openclaw devices approve \(requestId)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Text(l10n: "PAIRING_REQUIRED_TITLE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }

            Text(l10n: "PAIRING_REQUIRED_DESC")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.85))

            HStack(spacing: 6) {
                Text(command)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .lineLimit(1)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { copied = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(l10n: copied ? "PAIRING_COPIED" : "PAIRING_COPY_CMD")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(6)
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }

            Text(l10n: "PAIRING_REQUIRED_HINT")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.85), Color.indigo.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}
