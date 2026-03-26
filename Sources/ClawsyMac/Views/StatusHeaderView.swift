import SwiftUI
import ClawsyShared

/// Status header showing app name, host name, connection state, and indicator dot.
struct StatusHeaderView: View {
    @ObservedObject var hostManager: HostManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(l10n: "APP_NAME")
                        .font(.system(size: 13, weight: .semibold))
                    if let profile = hostManager.activeProfile {
                        Text(profile.name.isEmpty ? profile.gatewayHost : profile.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: profile.color) ?? .secondary)
                    }
                }

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.5), radius: 2)
                .accessibilityLabel(statusAccessibilityLabel)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var statusText: String {
        switch hostManager.state {
        case .disconnected:
            return NSLocalizedString("STATUS_DISCONNECTED", bundle: .clawsy, comment: "")
        case .connecting(let attempt):
            return String(format: NSLocalizedString("STATUS_CONNECTING %lld", bundle: .clawsy, comment: ""), attempt)
        case .sshTunneling:
            return NSLocalizedString("STATUS_STARTING_SSH", bundle: .clawsy, comment: "")
        case .handshaking:
            return NSLocalizedString("STATUS_HANDSHAKING", bundle: .clawsy, comment: "")
        case .awaitingPairing:
            return NSLocalizedString("STATUS_AWAITING_PAIR_APPROVE", bundle: .clawsy, comment: "")
        case .connected:
            return NSLocalizedString("STATUS_CONNECTED", bundle: .clawsy, comment: "")
        case .reconnecting(_, let seconds):
            return String(format: NSLocalizedString("STATUS_RECONNECT_COUNTDOWN %lld", bundle: .clawsy, comment: ""), seconds)
        case .failed(let failure):
            return failure.description
        }
    }

    private var statusColor: Color {
        switch hostManager.state {
        case .connected: return Color(red: 0.2, green: 0.78, blue: 0.35)
        case .connecting, .sshTunneling, .handshaking, .reconnecting: return Color(red: 0.95, green: 0.6, blue: 0.1)
        case .awaitingPairing: return .blue
        case .disconnected: return .gray
        case .failed: return Color(red: 0.9, green: 0.25, blue: 0.2)
        }
    }

    private var statusAccessibilityLabel: String {
        switch hostManager.state {
        case .connected:
            return NSLocalizedString("STATUS_CONNECTED", bundle: .clawsy, comment: "")
        case .connecting, .sshTunneling, .handshaking, .reconnecting:
            return NSLocalizedString("STATUS_CONNECTING_LABEL", bundle: .clawsy, comment: "")
        case .awaitingPairing:
            return NSLocalizedString("STATUS_AWAITING_PAIR_APPROVE", bundle: .clawsy, comment: "")
        case .disconnected:
            return NSLocalizedString("STATUS_DISCONNECTED", bundle: .clawsy, comment: "")
        case .failed:
            return NSLocalizedString("STATUS_FAILED_LABEL", bundle: .clawsy, comment: "")
        }
    }
}
