import SwiftUI
import ClawsyShared

struct AgentSetupView: View {
    @ObservedObject var hostManager: HostManager
    @Binding var isPresented: Bool
    var onShowManual: (() -> Void)? = nil

    @State private var pastedResponse = ""
    @State private var status: SetupStatus = .waiting
    @State private var promptCopied = false

    enum SetupStatus: Equatable {
        case waiting
        case success
        case error(String)
    }

    private static let agentPrompt = """
    I want to connect my Mac app "Clawsy" to this machine. \
    Please provide the gateway connection details in this exact format:

    CLAWSY-SETUP
    host: <gateway hostname or IP address>
    token: <gateway authentication token>

    The host should be just the hostname or IP (no protocol, no port). \
    The token is the authToken from your gateway config \
    (~/.openclaw/gateway.json).
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(l10n: "ADD_HOST_TITLE")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().clawsy()

            VStack(alignment: .leading, spacing: 20) {
                // Step 1: Copy prompt
                VStack(alignment: .leading, spacing: 8) {
                    Label(NSLocalizedString("AGENT_SETUP_STEP1_TITLE", bundle: .clawsy, comment: ""),
                          systemImage: "1.circle.fill")
                        .font(.system(size: 13, weight: .semibold))

                    Text(l10n: "AGENT_SETUP_STEP1_DESC")
                        .font(ClawsyTheme.Font.bannerBody)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: copyPrompt) {
                        HStack(spacing: 6) {
                            Image(systemName: promptCopied ? "checkmark" : "doc.on.doc")
                            Text(promptCopied
                                 ? NSLocalizedString("AGENT_SETUP_COPIED", bundle: .clawsy, comment: "")
                                 : NSLocalizedString("AGENT_SETUP_COPY_PROMPT", bundle: .clawsy, comment: ""))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                Divider().clawsy()

                // Step 2: Paste response
                VStack(alignment: .leading, spacing: 8) {
                    Label(NSLocalizedString("AGENT_SETUP_STEP2_TITLE", bundle: .clawsy, comment: ""),
                          systemImage: "2.circle.fill")
                        .font(.system(size: 13, weight: .semibold))

                    Text(l10n: "AGENT_SETUP_STEP2_DESC")
                        .font(ClawsyTheme.Font.bannerBody)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $pastedResponse)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(borderColor, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Status
                if case .error(let msg) = status {
                    Text(msg)
                        .font(ClawsyTheme.Font.bannerBody)
                        .foregroundColor(.red)
                }
                if status == .success {
                    Label(NSLocalizedString("AGENT_SETUP_SUCCESS", bundle: .clawsy, comment: ""),
                          systemImage: "checkmark.circle.fill")
                        .font(ClawsyTheme.Font.bannerBody)
                        .foregroundColor(.green)
                }
            }
            .padding(20)

            Spacer()
            Divider().clawsy()

            // Footer
            HStack {
                if let onShowManual {
                    Button(NSLocalizedString("AGENT_SETUP_MANUAL", bundle: .clawsy, comment: "")) {
                        onShowManual()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
                Spacer()
                Button(NSLocalizedString("AGENT_SETUP_CONNECT", bundle: .clawsy, comment: "")) {
                    applySetupCode()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(pastedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420, height: 440)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }

    private var borderColor: Color {
        switch status {
        case .error: return .red
        case .success: return .green
        default: return .secondary.opacity(0.3)
        }
    }

    private func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.agentPrompt, forType: .string)
        promptCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { promptCopied = false }
    }

    private func applySetupCode() {
        let text = pastedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Try line-based format: host: ... / token: ...
        if let result = parseLineFormat(text) {
            createHost(host: result.host, token: result.token)
            return
        }

        // Try existing base64 JSON format (backwards compat)
        if let result = parseBase64Format(text) {
            createHost(host: result.host, token: result.token)
            return
        }

        status = .error(NSLocalizedString("AGENT_SETUP_ERROR", bundle: .clawsy, comment: ""))
    }

    private func parseLineFormat(_ text: String) -> (host: String, token: String)? {
        let lines = text.components(separatedBy: .newlines)
        var host: String?
        var token: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("host:") {
                host = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("token:") {
                token = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
            }
        }

        guard let h = host, !h.isEmpty, let t = token, !t.isEmpty else { return nil }
        return (h, t)
    }

    private func parseBase64Format(_ text: String) -> (host: String, token: String)? {
        struct SetupPayload: Decodable { let url: String; let token: String }

        var code = text
        if code.contains("code="), let url = URLComponents(string: code),
           let codeParam = url.queryItems?.first(where: { $0.name == "code" })?.value {
            code = codeParam
        }

        var base64 = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let rem = base64.count % 4
        if rem != 0 { base64 += String(repeating: "=", count: 4 - rem) }

        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(SetupPayload.self, from: data),
              !payload.url.isEmpty, !payload.token.isEmpty
        else { return nil }

        let host: String
        if payload.url.contains("://") {
            host = URLComponents(string: payload.url)?.host ?? payload.url
        } else {
            host = payload.url.components(separatedBy: ":").first ?? payload.url
        }
        return (host, payload.token)
    }

    private func createHost(host: String, token: String) {
        let profileName = host.components(separatedBy: ".").first ?? host

        let profile = HostProfile(
            name: profileName,
            gatewayHost: host,
            gatewayPort: "18789",
            serverToken: token,
            useSshFallback: false
        )

        hostManager.addHost(profile)
        hostManager.connectHost(profile.id)
        status = .success

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isPresented = false
        }
    }
}
