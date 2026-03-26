import SwiftUI
import ClawsyShared

/// Agent picker shown when connected. Allows routing events to a specific agent.
/// Hidden when only one agent or not connected (clean UI paradigm).
struct AgentPickerView: View {
    @ObservedObject var hostManager: HostManager

    private var poller: GatewayPoller? { hostManager.activePoller }
    private var agents: [GatewayAgent] { poller?.agents ?? [] }

    private var targetSessionKey: Binding<String> {
        Binding<String>(
            get: { poller?.targetSessionKey ?? "main" },
            set: { newValue in
                guard let poller = poller else { return }
                if newValue == "main" {
                    poller.targetSessionKey = "main"
                    return
                }
                // Find the actual session key for this agent
                let agentId = String(newValue.dropFirst("agent:".count))
                let matching = poller.sessions.first { session in
                    let parts = session.id.split(separator: ":")
                    return parts.count >= 2 && parts[0] == "agent" && String(parts[1]) == agentId
                        && !session.id.contains(":cron:") && !session.id.contains(":subagent:")
                }
                poller.targetSessionKey = matching?.id ?? "agent:\(agentId):main"
            }
        )
    }

    var body: some View {
        if hostManager.isConnected && agents.count > 1 {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(l10n: "AGENT_PICKER_LABEL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: targetSessionKey) {
                    Text(NSLocalizedString("AGENT_PICKER_DEFAULT", bundle: .clawsy, comment: ""))
                        .tag("main")
                    ForEach(agents) { agent in
                        Text(agent.name).tag("agent:\(agent.id)")
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
