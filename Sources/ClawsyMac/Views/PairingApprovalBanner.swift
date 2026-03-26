import SwiftUI
import ClawsyShared

struct PairingApprovalBanner: View {
    let requestId: String
    @Binding var copied: Bool
    @State private var showShellCommand = false

    private var deviceId: String {
        DeviceIdentity.shared.deviceId
    }

    private var agentPrompt: String {
        "I have a pending Clawsy pairing request. Please run: openclaw devices list — then approve the pending request."
    }

    private var shellCommand: String {
        "openclaw devices list && openclaw devices approve <REQUEST_ID>"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            HStack {
                Image(systemName: ClawsyTheme.Icons.pairing)
                    .font(ClawsyTheme.Font.formLabel)
                    .foregroundColor(.white)
                Text(l10n: "PAIRING_REQUIRED_TITLE")
                    .font(ClawsyTheme.Font.bannerTitle)
                    .foregroundColor(.white)
                Spacer()
            }

            // Instruction
            Text(NSLocalizedString("PAIRING_SEND_HINT", bundle: .clawsy, comment: ""))
                .font(ClawsyTheme.Font.caption)
                .foregroundColor(.white.opacity(0.85))

            // Agent prompt (primary)
            HStack(spacing: 6) {
                Text(agentPrompt)
                    .font(ClawsyTheme.Font.caption)
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(agentPrompt, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { copied = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(ClawsyTheme.Font.caption)
                        Text(l10n: copied ? "PAIRING_COPIED" : "PAIRING_COPY_CMD")
                            .font(ClawsyTheme.Font.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(6)
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }

            // Shell command (secondary, expandable)
            Button(action: { withAnimation(ClawsyTheme.Animation.stateChange) { showShellCommand.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: showShellCommand ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                    Text(NSLocalizedString("PAIRING_TERMINAL_COMMAND", bundle: .clawsy, comment: ""))
                        .font(.system(size: 9))
                }
                .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            if showShellCommand {
                Text(shellCommand)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: ClawsyTheme.Spacing.cornerRadius + 2)
                .fill(ClawsyTheme.Colors.pairingBannerGradient)
        )
    }
}
