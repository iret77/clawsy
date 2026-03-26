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
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .accessibilityLabel(NSLocalizedString("CONNECTION_FAILURE_ICON", bundle: .clawsy, comment: ""))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if isRetryable {
                    Button(NSLocalizedString("RETRY", bundle: .clawsy, comment: ""), action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if needsRepair {
                    Button(NSLocalizedString("REPAIR_CONNECTION", bundle: .clawsy, comment: ""), action: onRepair)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .cornerRadius(8)
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
        case .unknown: return "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch failure {
        case .originNotAllowed: return "Origin Not Allowed"
        case .invalidToken: return "Invalid Token"
        case .sshTunnelFailed: return "SSH Tunnel Failed"
        case .hostUnreachable: return "Host Unreachable"
        case .gatewayNotRunning: return "Gateway Not Running"
        case .reconnectExhausted: return "Reconnect Exhausted"
        case .skillMissing: return "Clawsy Skill Missing"
        case .unknown: return "Connection Failed"
        }
    }

    private var detail: String {
        switch failure {
        case .originNotAllowed:
            return "The gateway rejected this connection. Check that Clawsy's origin is allowed in the gateway configuration."
        case .invalidToken:
            return "The authentication token was rejected. Try repairing the connection or entering a new token in settings."
        case .sshTunnelFailed(let reason):
            return "SSH tunnel could not be established: \(reason)"
        case .hostUnreachable:
            return "Cannot reach the gateway host. Check your network connection and firewall settings."
        case .gatewayNotRunning:
            return "The gateway is not responding. Make sure OpenClaw is running on the server."
        case .reconnectExhausted:
            return "Tried reconnecting for 30 minutes without success. Check that the server is online and try again."
        case .skillMissing:
            return "The Clawsy skill is not installed on the gateway."
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
