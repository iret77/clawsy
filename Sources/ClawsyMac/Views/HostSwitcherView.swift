import SwiftUI
import ClawsyShared

/// Horizontal pill row for switching between hosts. Shows per-host connection status dots.
struct HostSwitcherView: View {
    @ObservedObject var hostManager: HostManager
    var onHostAdded: ((HostProfile) -> Void)? = nil
    @State private var showingAddHost = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(hostManager.profiles) { profile in
                    let isActive = profile.id == hostManager.activeHostId
                    let hostState = hostManager.hostStates[profile.id]
                    let hostColor = Color(hex: profile.color) ?? .red

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hostManager.switchActiveHost(to: profile.id)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(dotColor(for: hostState?.connectionState))
                                .frame(width: 5, height: 5)
                            Text(profile.name.isEmpty ? profile.gatewayHost : profile.name)
                                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? .white : hostColor)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(isActive ? hostColor : Color.clear))
                        .overlay(Capsule().stroke(hostColor, lineWidth: isActive ? 0 : 1.5))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { showingAddHost = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
        .sheet(isPresented: $showingAddHost) {
            AddHostSheet(hostManager: hostManager, isPresented: $showingAddHost, onHostAdded: onHostAdded)
        }
    }

    private func dotColor(for state: ConnectionState?) -> Color {
        switch state {
        case .connected: return .green
        case .connecting, .sshTunneling, .handshaking, .reconnecting: return .orange
        case .awaitingPairing: return .blue
        default: return .secondary.opacity(0.5)
        }
    }
}

/// Empty state shown when no hosts are configured.
struct NoHostEmptyStateView: View {
    var onAddHost: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.45))
            VStack(spacing: 4) {
                Text(l10n: "NO_HOST_TITLE")
                    .font(.system(size: 13, weight: .semibold))
                Text(l10n: "NO_HOST_SUBTITLE")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onAddHost) {
                Label(NSLocalizedString("NO_HOST_ADD_BUTTON", bundle: .clawsy, comment: ""), systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
    }
}
