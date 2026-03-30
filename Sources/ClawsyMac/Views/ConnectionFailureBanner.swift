import SwiftUI
import ClawsyShared

/// Banner shown when the connection has failed. Provides actionable retry/repair options.
struct ConnectionFailureBanner: View {
    let failure: ConnectionFailure
    var onRetry: () -> Void
    var onRepair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(ClawsyTheme.Font.menuItem)
                    .foregroundColor(ClawsyTheme.Colors.failed)
                    .accessibilityLabel(NSLocalizedString("CONNECTION_FAILURE_ICON", bundle: .clawsy, comment: ""))
                Text(title)
                    .font(ClawsyTheme.Font.bannerTitle)
                    .foregroundColor(.primary)
            }

            Text(detail)
                .font(ClawsyTheme.Font.bannerBody)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if isRetryable {
                    Button(action: onRetry) {
                        Label(NSLocalizedString("FAILURE_RETRY", bundle: .clawsy, comment: ""), systemImage: ClawsyTheme.Icons.retry)
                            .font(ClawsyTheme.Font.bannerBody)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if needsRepair {
                    Button(action: onRepair) {
                        Label(NSLocalizedString("REPAIR_CONNECTION", bundle: .clawsy, comment: ""), systemImage: ClawsyTheme.Icons.repair)
                            .font(ClawsyTheme.Font.bannerBody)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClawsyTheme.Colors.errorBannerBackground)
        .cornerRadius(ClawsyTheme.Spacing.cornerRadius)
    }

    private var icon: String {
        switch failure {
        case .originNotAllowed: return "lock.shield"
        case .invalidToken: return "key.slash"
        case .sshTunnelFailed: return "terminal"
        case .hostUnreachable: return "wifi.slash"
        case .gatewayNotRunning: return "server.rack"
        case .reconnectExhausted: return "clock.badge.exclamationmark"
        case .skillMissing: return "puzzlepiece.extension"
        case .unknown: return ClawsyTheme.Icons.warning
        }
    }

    private var title: String {
        switch failure {
        case .originNotAllowed: return NSLocalizedString("FAILURE_ORIGIN_NOT_ALLOWED", bundle: .clawsy, comment: "")
        case .invalidToken: return NSLocalizedString("FAILURE_INVALID_TOKEN", bundle: .clawsy, comment: "")
        case .sshTunnelFailed: return NSLocalizedString("FAILURE_SSH_FAILED", bundle: .clawsy, comment: "")
        case .hostUnreachable: return NSLocalizedString("FAILURE_HOST_UNREACHABLE", bundle: .clawsy, comment: "")
        case .gatewayNotRunning: return NSLocalizedString("FAILURE_GATEWAY_NOT_RUNNING", bundle: .clawsy, comment: "")
        case .reconnectExhausted: return NSLocalizedString("FAILURE_RECONNECT_EXHAUSTED", bundle: .clawsy, comment: "")
        case .skillMissing: return NSLocalizedString("FAILURE_SKILL_MISSING", bundle: .clawsy, comment: "")
        case .unknown: return NSLocalizedString("FAILURE_UNKNOWN", bundle: .clawsy, comment: "")
        }
    }

    private var detail: String {
        switch failure {
        case .originNotAllowed:
            return NSLocalizedString("FAILURE_ORIGIN_DETAIL", bundle: .clawsy, comment: "")
        case .invalidToken:
            return NSLocalizedString("FAILURE_TOKEN_DETAIL", bundle: .clawsy, comment: "")
        case .sshTunnelFailed(let reason):
            return String(format: NSLocalizedString("FAILURE_SSH_DETAIL %@", bundle: .clawsy, comment: ""), reason)
        case .hostUnreachable:
            return NSLocalizedString("FAILURE_UNREACHABLE_DETAIL", bundle: .clawsy, comment: "")
        case .gatewayNotRunning:
            return NSLocalizedString("FAILURE_GATEWAY_DETAIL", bundle: .clawsy, comment: "")
        case .reconnectExhausted:
            return NSLocalizedString("FAILURE_RECONNECT_DETAIL", bundle: .clawsy, comment: "")
        case .skillMissing:
            return NSLocalizedString("FAILURE_SKILL_DETAIL", bundle: .clawsy, comment: "")
        case .unknown(let detail):
            return detail
        }
    }

    private var isRetryable: Bool {
        switch failure {
        case .hostUnreachable, .gatewayNotRunning, .reconnectExhausted, .sshTunnelFailed, .unknown: return true
        default: return false
        }
    }

    private var needsRepair: Bool {
        switch failure {
        case .invalidToken, .originNotAllowed: return true
        default: return false
        }
    }
}
