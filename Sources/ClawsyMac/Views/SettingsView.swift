import SwiftUI
import ClawsyShared

// MARK: - Settings Tab View (macOS Preferences Window)

struct SettingsTabView: View {
    @ObservedObject var hostManager: HostManager
    @Binding var isPresented: Bool

    @State private var editedProfile: HostProfile = HostProfile(
        name: "", gatewayHost: "", gatewayPort: "18789", serverToken: ""
    )
    @State private var hostToDelete: HostProfile? = nil
    @State private var showDeleteConfirm = false
    @State private var selectedTab: SettingsTab = .general

    @AppStorage("quickSendHotkey", store: SharedConfig.sharedDefaults) private var quickSendHotkey = "K"
    @AppStorage("pushClipboardHotkey", store: SharedConfig.sharedDefaults) private var pushClipboardHotkey = "V"
    @AppStorage("cameraHotkey", store: SharedConfig.sharedDefaults) private var cameraHotkey = "P"
    @AppStorage("screenshotFullHotkey", store: SharedConfig.sharedDefaults) private var screenshotFullHotkey = "S"
    @AppStorage("screenshotAreaHotkey", store: SharedConfig.sharedDefaults) private var screenshotAreaHotkey = "A"

    @ObservedObject var updateManager = UpdateManager.shared

    enum SettingsTab: Hashable {
        case general, connection, shortcuts
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label(NSLocalizedString("SETTINGS_TAB_GENERAL", bundle: .clawsy, comment: ""),
                          systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            connectionTab
                .tabItem {
                    Label(NSLocalizedString("SETTINGS_TAB_CONNECTION", bundle: .clawsy, comment: ""),
                          systemImage: "network")
                }
                .tag(SettingsTab.connection)

            shortcutsTab
                .tabItem {
                    Label(NSLocalizedString("SETTINGS_TAB_SHORTCUTS", bundle: .clawsy, comment: ""),
                          systemImage: "keyboard")
                }
                .tag(SettingsTab.shortcuts)
        }
        .frame(width: 480, height: 370)
        .onAppear { loadActiveProfile() }
        .onChange(of: hostManager.activeHostId) { _ in loadActiveProfile() }
        .onDisappear { saveProfile() }
        .alert("Delete Host?", isPresented: $showDeleteConfirm) {
            Button(NSLocalizedString("CANCEL", bundle: .clawsy, comment: ""), role: .cancel) { hostToDelete = nil }
            Button(NSLocalizedString("DELETE_HOST_CONFIRM", bundle: .clawsy, comment: ""), role: .destructive) {
                if let host = hostToDelete { hostManager.removeHost(id: host.id) }
                hostToDelete = nil
            }
        } message: {
            Text(NSLocalizedString("SETTINGS_DELETE_HOST_CONFIRM", bundle: .clawsy, comment: ""))
        }
    }

    // MARK: - Tab: General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Host Identity
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    formRow("Name", text: $editedProfile.name)

                    HStack(spacing: 8) {
                        Text(NSLocalizedString("SETTINGS_SECTION_SHARED_FOLDER", bundle: .clawsy, comment: ""))
                            .font(ClawsyTheme.Font.formLabel)
                            .frame(width: labelWidth, alignment: .trailing)
                        Image(systemName: "folder.fill")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.system(size: 12))
                        Text(editedProfile.sharedFolderPath.isEmpty ? "~/Documents/Clawsy" : editedProfile.sharedFolderPath)
                            .font(ClawsyTheme.Font.code)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(NSLocalizedString("SETTINGS_CHANGE_FOLDER", bundle: .clawsy, comment: "")) {
                            selectFolder()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            } label: {
                sectionLabel("Host", icon: "person.crop.circle")
            }

            // Notifications
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 12))
                        Text(NSLocalizedString("SETTINGS_RESPONSE_CLAWSY", bundle: .clawsy, comment: ""))
                            .font(ClawsyTheme.Font.formLabel)
                    }
                    Text(NSLocalizedString("SETTINGS_RESPONSE_CHANNEL_HINT", bundle: .clawsy, comment: ""))
                        .font(ClawsyTheme.Font.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            } label: {
                sectionLabel(NSLocalizedString("SETTINGS_SECTION_RESPONSE", bundle: .clawsy, comment: ""),
                             icon: "arrowshape.turn.up.left.circle")
            }

            Spacer()

            // Footer: Version + Tools
            HStack(spacing: 16) {
                toolLink(icon: ClawsyTheme.Icons.debug, label: NSLocalizedString("DEBUG_LOG", bundle: .clawsy, comment: ""), color: .accentColor) {
                    openDebugLog()
                }
                toolLink(icon: ClawsyTheme.Icons.update,
                         label: updateManager.updateAvailable
                            ? "Update: \(updateManager.updateVersion)"
                            : NSLocalizedString("SETTINGS_CHECK_UPDATES", bundle: .clawsy, comment: ""),
                         color: .accentColor) {
                    if updateManager.updateAvailable {
                        updateManager.downloadAndInstall()
                    } else {
                        updateManager.checkForUpdates(silent: false)
                    }
                }
                toolLink(icon: ClawsyTheme.Icons.repair, label: NSLocalizedString("REPAIR_CONNECTION", bundle: .clawsy, comment: ""), color: .orange) {
                    hostManager.repairActiveConnection()
                }
                Spacer()
                Text(SharedConfig.versionDisplay)
                    .font(ClawsyTheme.Font.footer)
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(20)
    }

    // MARK: - Tab: Connection

    private var connectionTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Server
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    formRow("Host", text: $editedProfile.gatewayHost)
                    HStack(spacing: 0) {
                        formRow("Port", text: $editedProfile.gatewayPort)
                            .frame(maxWidth: labelWidth + 80)
                        Spacer()
                    }
                    HStack {
                        Text("Token")
                            .font(ClawsyTheme.Font.formLabel)
                            .frame(width: labelWidth, alignment: .trailing)
                        SecureField("", text: $editedProfile.serverToken)
                            .textFieldStyle(.roundedBorder)
                            .font(ClawsyTheme.Font.formValue)
                    }
                }
                .padding(.vertical, 2)
            } label: {
                sectionLabel("Server", icon: "server.rack")
            }

            // SSH
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    formRow("SSH User", text: $editedProfile.sshUser)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $editedProfile.useSshFallback) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("SSH Fallback")
                                    .font(ClawsyTheme.Font.formLabel)
                                Text(NSLocalizedString("SSH_FALLBACK_DESC", bundle: .clawsy, comment: ""))
                                    .font(ClawsyTheme.Font.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(editedProfile.sshUser.isEmpty)
                        .onChange(of: editedProfile.useSshFallback) { enabled in
                            if !enabled { editedProfile.sshOnly = false }
                        }

                        Toggle(isOn: $editedProfile.sshOnly) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(NSLocalizedString("SSH_ONLY_MODE", bundle: .clawsy, comment: ""))
                                    .font(ClawsyTheme.Font.formLabel)
                                Text(NSLocalizedString("SSH_ONLY_MODE_DESC", bundle: .clawsy, comment: ""))
                                    .font(ClawsyTheme.Font.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!editedProfile.useSshFallback || editedProfile.sshUser.isEmpty)
                    }
                    .padding(.leading, labelWidth + 8)
                }
                .padding(.vertical, 2)
            } label: {
                sectionLabel("SSH", icon: "terminal")
            }

            // Node Mode
            GroupBox {
                Toggle(isOn: $editedProfile.enableNodeConnection) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(NSLocalizedString("NODE_MODE_LABEL", bundle: .clawsy, comment: ""))
                            .font(ClawsyTheme.Font.formLabel)
                        Text(NSLocalizedString("NODE_MODE_DESC", bundle: .clawsy, comment: ""))
                            .font(ClawsyTheme.Font.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.vertical, 2)
            } label: {
                sectionLabel("Node", icon: "point.3.connected.trianglepath.dotted")
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Tab: Shortcuts

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("SETTINGS_HOTKEYS_HINT", bundle: .clawsy, comment: ""))
                        .font(ClawsyTheme.Font.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)

                    hotkeyRow("Quick Send", key: $quickSendHotkey)
                    Divider().clawsy()
                    hotkeyRow("Clipboard", key: $pushClipboardHotkey)
                    Divider().clawsy()
                    hotkeyRow("Camera", key: $cameraHotkey)
                    Divider().clawsy()
                    hotkeyRow("Full Screenshot", key: $screenshotFullHotkey)
                    Divider().clawsy()
                    hotkeyRow("Area Screenshot", key: $screenshotAreaHotkey)
                }
                .padding(.vertical, 4)
            } label: {
                sectionLabel(NSLocalizedString("SETTINGS_SECTION_HOTKEYS", bundle: .clawsy, comment: ""),
                             icon: ClawsyTheme.Icons.hotkey)
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Shared Components

    private let labelWidth: CGFloat = 70

    private func sectionLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(ClawsyTheme.Font.sectionHeader)
            .foregroundColor(.secondary)
    }

    private func formRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(ClawsyTheme.Font.formLabel)
                .frame(width: labelWidth, alignment: .trailing)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(ClawsyTheme.Font.formValue)
        }
    }

    private func hotkeyRow(_ label: String, key: Binding<String>) -> some View {
        HStack {
            Text(label).font(ClawsyTheme.Font.formLabel)
            Spacer()
            HStack(spacing: 2) {
                Text("⌘⇧")
                    .font(ClawsyTheme.Font.caption)
                    .foregroundColor(.secondary)
                TextField("", text: key)
                    .textFieldStyle(.roundedBorder)
                    .font(ClawsyTheme.Font.formValue)
                    .frame(width: 36)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func toolLink(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(ClawsyTheme.Font.caption)
            }
            .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func loadActiveProfile() {
        if let active = hostManager.activeProfile {
            editedProfile = active
        }
    }

    private func saveProfile() {
        if editedProfile.name.trimmingCharacters(in: .whitespaces).isEmpty {
            editedProfile.name = editedProfile.gatewayHost
        }
        if editedProfile.sshUser.isEmpty {
            editedProfile.useSshFallback = false
            editedProfile.sshOnly = false
        }
        if !editedProfile.useSshFallback {
            editedProfile.sshOnly = false
        }
        hostManager.updateHost(editedProfile)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("SELECT_SHARED_FOLDER", bundle: .clawsy, comment: "")

        if !editedProfile.sharedFolderPath.isEmpty {
            let resolved = editedProfile.sharedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
            panel.directoryURL = URL(fileURLWithPath: resolved)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            var path = url.path
            if path.hasPrefix(NSHomeDirectory()) {
                path = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            }
            if let data = try? url.bookmarkData(options: .withSecurityScope) {
                SharedConfig.resolvedFolderUrl?.stopAccessingSecurityScopedResource()
                if url.startAccessingSecurityScopedResource() {
                    SharedConfig.resolvedFolderUrl = url
                }
                SharedConfig.sharedFolderBookmark = data
            }
            editedProfile.sharedFolderPath = path
        }
    }

    private func openDebugLog() {
        // Post notification for AppDelegate to handle
        NotificationCenter.default.post(name: .init("ai.clawsy.openDebugLog"), object: nil)
    }
}
