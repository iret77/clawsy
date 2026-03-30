import SwiftUI
import ClawsyShared

struct AddHostSheet: View {
    @ObservedObject var hostManager: HostManager
    @Binding var isPresented: Bool
    var onHostAdded: ((HostProfile) -> Void)? = nil

    @State private var name = ""
    @State private var host = ""
    @State private var port = "18789"
    @State private var token = ""
    @State private var sshUser = ""
    @State private var useSshFallback = false
    @State private var sshOnly = false
    @State private var enableNodeConnection = true
    @State private var selectedColor = HostProfile.defaultColors[1]

    private var canSave: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Identity
                    VStack(alignment: .leading, spacing: 8) {
                        Label(NSLocalizedString("ADD_HOST_SECTION_IDENTITY", bundle: .clawsy, comment: ""), systemImage: "tag.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        TextField("Name (optional)", text: $name)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 6) {
                            Text(NSLocalizedString("ADD_HOST_SECTION_COLOR", bundle: .clawsy, comment: "")).font(ClawsyTheme.Font.bannerBody).foregroundColor(.secondary)
                            Spacer()
                            ForEach(HostProfile.defaultColors, id: \.self) { hex in
                                let c = Color(hex: hex) ?? .red
                                Circle()
                                    .fill(c)
                                    .frame(width: 18, height: 18)
                                    .overlay(selectedColor == hex ?
                                        Circle().stroke(Color.white, lineWidth: 2).shadow(radius: 1) : nil)
                                    .onTapGesture { selectedColor = hex }
                            }
                        }
                    }

                    Divider().clawsy()

                    // Connection
                    VStack(alignment: .leading, spacing: 8) {
                        Label(NSLocalizedString("ADD_HOST_SECTION_CONNECTION", bundle: .clawsy, comment: ""), systemImage: "network")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        TextField("Gateway Host", text: $host)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            TextField("Port", text: $port)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Spacer()
                        }
                        SecureField("Gateway Token", text: $token)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider().clawsy()

                    // SSH
                    VStack(alignment: .leading, spacing: 8) {
                        Label(NSLocalizedString("ADD_HOST_SECTION_SSH", bundle: .clawsy, comment: ""), systemImage: "terminal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        TextField("SSH User", text: $sshUser)
                            .textFieldStyle(.roundedBorder)
                        Toggle("SSH Fallback", isOn: $useSshFallback)
                            .font(ClawsyTheme.Font.formLabel)
                            .onChange(of: useSshFallback) { enabled in
                                if !enabled { sshOnly = false }
                            }
                        Toggle("SSH Only", isOn: $sshOnly)
                            .font(ClawsyTheme.Font.formLabel)
                            .disabled(!useSshFallback || sshUser.isEmpty)
                    }

                    Divider().clawsy()

                    // Node Mode
                    VStack(alignment: .leading, spacing: 8) {
                        Label(NSLocalizedString("NODE_MODE_SECTION", bundle: .clawsy, comment: ""), systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        Toggle(NSLocalizedString("NODE_MODE_LABEL", bundle: .clawsy, comment: ""), isOn: $enableNodeConnection)
                            .font(ClawsyTheme.Font.formLabel)
                        Text(NSLocalizedString("NODE_MODE_DESC", bundle: .clawsy, comment: ""))
                            .font(ClawsyTheme.Font.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
            }

            Divider().clawsy()

            // Footer
            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                Spacer()
                Button("Add Host") { addHost() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 380, height: 640)
    }

    private func addHost() {
        let profileName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? host.components(separatedBy: ".").first ?? host
            : name

        let profile = HostProfile(
            name: profileName,
            gatewayHost: host.trimmingCharacters(in: .whitespaces),
            gatewayPort: port.isEmpty ? "18789" : port,
            serverToken: token.trimmingCharacters(in: .whitespaces),
            sshUser: sshUser.trimmingCharacters(in: .whitespaces),
            useSshFallback: useSshFallback,
            sshOnly: sshOnly,
            enableNodeConnection: enableNodeConnection,
            color: selectedColor
        )
        onHostAdded?(profile)
        isPresented = false
    }
}
