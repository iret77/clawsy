import SwiftUI
import ClawsyShared

/// Agent picker shown when connected. Allows routing events to a specific agent.
/// Hidden when only one agent or not connected (clean UI paradigm).
struct AgentPickerView: View {
    @ObservedObject var hostManager: HostManager

    var body: some View {
        if let poller = hostManager.activePoller, hostManager.isConnected, poller.agents.count > 1 {
            AgentPickerContent(poller: poller)
        }
    }
}

/// Inner view that directly observes the GatewayPoller.
/// This is necessary because the Picker binding must be backed by an observed
/// property — otherwise SwiftUI doesn't see changes to targetSessionKey.
private struct AgentPickerContent: View {
    @ObservedObject var poller: GatewayPoller

    /// Extract agent ID from session key format "agent:<id>:main" → "<id>"
    private var selectedAgentId: String {
        let key = poller.targetSessionKey
        if key == "main" || key.isEmpty { return poller.agents.first?.id ?? "" }
        let parts = key.split(separator: ":")
        if parts.count >= 2, parts[0] == "agent" {
            return String(parts[1])
        }
        return key
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .font(ClawsyTheme.Font.bannerBody)
                .foregroundColor(.secondary)
            Text(l10n: "AGENT_PICKER_LABEL")
                .font(ClawsyTheme.Font.headerHostName)
                .foregroundColor(.secondary)
            Spacer()
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
            .frame(maxWidth: 160)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
