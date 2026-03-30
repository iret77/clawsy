import SwiftUI
import ClawsyShared

/// Agent picker — compact Apple-style row integrated into the popover header area.
/// Shows current agent name with a menu picker for switching.
/// Hidden when not connected or only one agent exists.
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
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if poller.agents.count > 1 {
                // Multiple agents: show picker
                Picker("", selection: Binding(
                    get: { selectedAgentId },
                    set: { agentId in
                        poller.targetSessionKey = "agent:\(agentId):main"
                    }
                )) {
                    ForEach(poller.agents) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
            } else {
                // Single agent: just show name
                Text(selectedAgentName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Agent count badge
            if poller.agents.count > 1 {
                Text("\(poller.agents.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
        }
        .padding(.horizontal, ClawsyTheme.Spacing.contentH)
        .padding(.vertical, 5)
    }
}
