import SwiftUI
import ClawsyShared

struct PairingApprovalBanner: View {
    let requestId: String
    @Binding var copied: Bool
    @State private var showShellCommand = false

    private var deviceIdShort: String {
        String(DeviceIdentity.shared.deviceId.prefix(12))
    }

    private var agentPrompt: String {
        "Please approve my new Clawsy device (ID starts with \(deviceIdShort)…)"
    }

    private var shellCommand: String {
        "openclaw devices list && openclaw devices approve <REQUEST_ID>"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            HStack {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Text(l10n: "PAIRING_REQUIRED_TITLE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }

            // Instruction
            Text("Send this to your OpenClaw agent:")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.85))

            // Agent prompt (primary)
            HStack(spacing: 6) {
                Text(agentPrompt)
                    .font(.system(size: 10))
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

            // Shell command (secondary, expandable)
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showShellCommand.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: showShellCommand ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                    Text("Terminal command")
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
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.85), Color.indigo.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}
