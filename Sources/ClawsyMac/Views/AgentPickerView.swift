import SwiftUI
import ClawsyShared

/// Agent picker shown when connected. Allows routing events to a specific agent.
/// Hidden when only one agent or not connected (clean UI paradigm).
struct AgentPickerView: View {
    @ObservedObject var hostManager: HostManager

    private var poller: GatewayPoller? { hostManager.activePoller }
    private var agents: [GatewayAgent] { poller?.agents ?? [] }

    /// Selected agent ID binding (agent IDs like "main", "cyberclaw", etc.)
    private var selectedAgentId: Binding<String> {
        Binding<String>(
            get: {
                // Extract agent ID from stored targetSessionKey
                let key = poller?.targetSessionKey ?? "main"
                if key == "main" { return "main" }
                // "agent:cyberclaw:main" → "cyberclaw"
                let parts = key.split(separator: ":")
                if parts.count >= 2, parts[0] == "agent" {
                    return String(parts[1])
                }
                return key
            },
            set: { agentId in
                guard let poller = poller else { return }
                if agentId == "main" {
                    poller.targetSessionKey = "main"
                } else {
                    poller.targetSessionKey = "agent:\(agentId):main"
                }
            }
        )
    }

    var body: some View {
        if hostManager.isConnected && agents.count > 1 {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(ClawsyTheme.Font.bannerBody)
                    .foregroundColor(.secondary)
                Text(l10n: "AGENT_PICKER_LABEL")
                    .font(ClawsyTheme.Font.headerHostName)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: selectedAgentId) {
                    ForEach(agents) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}
