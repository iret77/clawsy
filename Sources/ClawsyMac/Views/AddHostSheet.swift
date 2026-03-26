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
    @State private var useSshFallback = true
    @State private var sshOnly = false
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

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Identity
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Identity", systemImage: "tag.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        TextField("Name (optional)", text: $name)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 6) {
                            Text("Color").font(.system(size: 11)).foregroundColor(.secondary)
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

                    Divider().opacity(0.2)

                    // Connection
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Connection", systemImage: "network")
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

                    Divider().opacity(0.2)

                    // SSH
                    VStack(alignment: .leading, spacing: 8) {
                        Label("SSH (optional)", systemImage: "terminal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        TextField("SSH User", text: $sshUser)
                            .textFieldStyle(.roundedBorder)
                        Toggle("SSH Fallback", isOn: $useSshFallback)
                            .font(.system(size: 12))
                        Toggle("SSH Only", isOn: $sshOnly)
                            .font(.system(size: 12))
                    }
                }
                .padding(20)
            }

            Divider().opacity(0.3)

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
        .frame(width: 380, height: 520)
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
            color: selectedColor
        )
        onHostAdded?(profile)
        isPresented = false
    }
}
