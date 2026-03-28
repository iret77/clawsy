import SwiftUI
import ClawsyShared

/// Shows which agent Clawsy is currently communicating with.
/// - 1 agent: displays agent name (no picker, just info)
/// - Multiple agents: dropdown picker to choose target
/// - Not connected or no agents: hidden
struct AgentPickerView: View {
    @ObservedObject var hostManager: HostManager

    private var poller: GatewayPoller? { hostManager.activePoller }
    private var agents: [GatewayAgent] { poller?.agents ?? [] }

    /// The display name of the currently targeted agent
    private var currentAgentName: String {
        guard let poller = poller else { return "Agent" }
        let key = poller.targetSessionKey
        // Match by agent ID in session key (e.g. "agent:cyberclaw:main")
        if let agent = agents.first(where: { key.contains($0.id) }) {
            return agent.name
        }
        return agents.first?.name ?? "Agent"
    }

    private var targetSessionKey: Binding<String> {
        Binding<String>(
            get: { poller?.targetSessionKey ?? "main" },
            set: { newValue in
                guard let poller = poller else { return }
                if newValue == "main" {
                    poller.targetSessionKey = "main"
                    return
                }
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
        if hostManager.isConnected && !agents.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)

                if agents.count == 1 {
                    // Single agent — show name, no picker
                    Text(currentAgentName)
                        .font(ClawsyTheme.Font.headerHostName)
                        .foregroundColor(.primary)
                } else {
                    // Multiple agents — dropdown picker
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

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}
