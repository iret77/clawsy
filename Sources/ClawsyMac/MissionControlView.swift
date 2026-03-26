import SwiftUI
import ClawsyShared

struct MissionControlView: View {
    @ObservedObject var hostManager: HostManager

    private var sessions: [GatewaySession] {
        hostManager.activePoller?.sessions ?? []
    }

    private var runningSessions: [GatewaySession] {
        sessions.filter { $0.status == "running" }
    }

    private var recentSessions: [GatewaySession] {
        sessions.filter { $0.status != "running" }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text(l10n: "MISSION_CONTROL_TITLE")
                    .font(.headline)
                Spacer()
                if !runningSessions.isEmpty {
                    Text("\(runningSessions.count) active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.accentColor)
            }

            if !hostManager.isConnected {
                // Offline state
                VStack(spacing: 10) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Connect to see agent activity")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if runningSessions.isEmpty && recentSessions.isEmpty {
                // Empty state
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(l10n: "MISSION_CONTROL_EMPTY")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(l10n: "MISSION_CONTROL_EMPTY_HINT")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        // Running sessions (active tasks)
                        ForEach(runningSessions) { session in
                            SessionRowView(session: session, isActive: true)
                        }

                        // Recent sessions (completed/idle)
                        if !recentSessions.isEmpty && !runningSessions.isEmpty {
                            Divider().padding(.vertical, 4)
                            HStack {
                                Text("Recent")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        ForEach(recentSessions) { session in
                            SessionRowView(session: session, isActive: false)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .frame(width: 320, height: 380)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
    }
}

// MARK: - Session Row

private struct SessionRowView: View {
    let session: GatewaySession
    let isActive: Bool
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var displayName: String {
        if let label = session.label, !label.isEmpty { return label }
        let parts = session.id.split(separator: ":")
        if parts.count >= 3 { return String(parts[2]) }
        return session.id
    }

    private var shortModel: String? {
        guard let m = session.model else { return nil }
        if m.contains("/") { return String(m.split(separator: "/").last ?? Substring(m)) }
        return m
    }

    private var statusColor: Color {
        switch session.status {
        case "running": return .green
        case "done": return .secondary
        case "error": return .red
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .overlay(
                    isActive ?
                        Circle()
                            .stroke(statusColor.opacity(0.4), lineWidth: 2)
                            .frame(width: 10, height: 10)
                        : nil
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    if let task = session.task {
                        Text("— \(task)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if let model = shortModel {
                    Text(model)
                        .font(.system(size: 9))
                        .foregroundColor(modelBadgeColor(for: session.model))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Elapsed time
            if isActive {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text(formatElapsed(elapsed))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isActive ? statusColor.opacity(0.06) : Color.clear)
        .cornerRadius(6)
        .onAppear {
            if let started = session.startedAt {
                elapsed = Date().timeIntervalSince(started)
            }
        }
        .onReceive(timer) { _ in
            guard isActive else { return }
            if let started = session.startedAt {
                elapsed = Date().timeIntervalSince(started)
            } else {
                elapsed += 1
            }
        }
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(0, interval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 { return "0:\(String(format: "%02d", seconds))" }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - Model Badge Color

private func modelBadgeColor(for model: String?) -> Color {
    guard let m = model?.lowercased() else { return .secondary }
    if m.contains("claude") { return Color(red: 0.6, green: 0.4, blue: 0.9) }
    if m.contains("gpt") { return .green }
    if m.contains("gemini") { return .blue }
    if m.contains("llama") { return .orange }
    return .secondary
}
