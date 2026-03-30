import SwiftUI
import ClawsyShared

/// Agent picker — Apple-style disclosure list (like WLAN network selection).
/// Shows active agent with checkmark, tap to switch.
struct AgentPickerView: View {
    @ObservedObject var hostManager: HostManager

    var body: some View {
        if let poller = hostManager.activePoller, !poller.agents.isEmpty {
            AgentPickerContent(poller: poller)
        }
    }
}

private struct AgentPickerContent: View {
    @ObservedObject var poller: GatewayPoller
    @State private var isExpanded = false

    private var selectedAgentId: String {
        let key = poller.targetSessionKey
        if key == "main" || key.isEmpty { return poller.agents.first?.id ?? "" }
        let parts = key.split(separator: ":")
        if parts.count >= 2, parts[0] == "agent" {
            return String(parts[1])
        }
        return key
    }

    private var selectedAgentName: String {
        poller.agents.first(where: { $0.id == selectedAgentId })?.name
            ?? poller.agents.first?.name ?? "Agent"
    }

    var body: some View {
        VStack(spacing: 0) {
            if poller.agents.count <= 1 {
                // Single agent — simple row, no disclosure
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(selectedAgentName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, ClawsyTheme.Spacing.contentH)
                .padding(.vertical, 6)
            } else {
                // Multiple agents — disclosure group like Apple WLAN
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("AGENT_PICKER_LABEL", bundle: .clawsy, comment: ""))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(selectedAgentName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.5))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .padding(.horizontal, ClawsyTheme.Spacing.contentH)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(poller.agents) { agent in
                            Button(action: {
                                poller.targetSessionKey = "agent:\(agent.id):main"
                            }) {
                                HStack(spacing: 8) {
                                    // Checkmark for active agent
                                    Image(systemName: agent.id == selectedAgentId ? "checkmark" : "")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 14)

                                    Text(agent.name)
                                        .font(.system(size: 12))
                                        .foregroundColor(.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, ClawsyTheme.Spacing.contentH + 6)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(AgentRowButtonStyle())
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

/// Hover-highlighting button style for agent rows
private struct AgentRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? ClawsyTheme.Colors.hoverBackground : Color.clear)
                    .padding(.horizontal, 4)
            )
            .onHover { hovering in
                withAnimation(ClawsyTheme.Animation.hover) { isHovering = hovering }
            }
    }
}
