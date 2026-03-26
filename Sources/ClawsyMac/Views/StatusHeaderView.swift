import SwiftUI
import ClawsyShared

/// Status header showing app name, host name, connection state, and animated indicator.
struct StatusHeaderView: View {
    @ObservedObject var hostManager: HostManager
    @State private var isPulsing = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(l10n: "APP_NAME")
                        .font(ClawsyTheme.Font.headerTitle)
                    if let profile = hostManager.activeProfile {
                        Text(profile.name.isEmpty ? profile.gatewayHost : profile.name)
                            .font(ClawsyTheme.Font.headerHostName)
                            .foregroundColor(Color(hex: profile.color) ?? .secondary)
                    }
                }

                Text(statusText)
                    .font(ClawsyTheme.Font.headerStatus)
                    .foregroundColor(.secondary)
                    .animation(ClawsyTheme.Animation.stateChange, value: hostManager.state)
            }

            Spacer()

            // Animated status indicator
            statusIndicator
                .accessibilityLabel(statusAccessibilityLabel)
        }
        .padding(.horizontal, ClawsyTheme.Spacing.contentH)
        .padding(.top, ClawsyTheme.Spacing.headerTop)
        .padding(.bottom, ClawsyTheme.Spacing.headerBottom)
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch hostManager.state {
        case .connected:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundColor(ClawsyTheme.Colors.connected)

        case .connecting, .sshTunneling, .handshaking, .reconnecting:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundColor(ClawsyTheme.Colors.connecting)
                .opacity(isPulsing ? 0.3 : 1.0)
                .onAppear { isPulsing = true }
                .onDisappear { isPulsing = false }
                .animation(ClawsyTheme.Animation.pulse, value: isPulsing)

        case .awaitingPairing:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundColor(ClawsyTheme.Colors.pairing)

        case .disconnected:
            Image(systemName: "circle")
                .font(.system(size: 8))
                .foregroundColor(ClawsyTheme.Colors.disconnected)

        case .failed:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundColor(ClawsyTheme.Colors.failed)
        }
    }

    // MARK: - Status Text

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
