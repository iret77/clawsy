import SwiftUI
import ClawsyShared

struct SettingsView: View {
    @ObservedObject var hostManager: HostManager
    @Binding var isPresented: Bool
    var onShowDebugLog: (() -> Void)? = nil
    var onHostAdded: ((HostProfile) -> Void)? = nil

    @State private var editedProfile: HostProfile = HostProfile(
        name: "", gatewayHost: "", gatewayPort: "18789", serverToken: ""
    )
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var hostToDelete: HostProfile? = nil
    @State private var showDeleteConfirm = false

    @AppStorage("quickSendHotkey", store: SharedConfig.sharedDefaults) private var quickSendHotkey = "K"
    @AppStorage("pushClipboardHotkey", store: SharedConfig.sharedDefaults) private var pushClipboardHotkey = "V"
    @AppStorage("cameraHotkey", store: SharedConfig.sharedDefaults) private var cameraHotkey = "P"
    @AppStorage("screenshotFullHotkey", store: SharedConfig.sharedDefaults) private var screenshotFullHotkey = "S"
    @AppStorage("screenshotAreaHotkey", store: SharedConfig.sharedDefaults) private var screenshotAreaHotkey = "A"

    @ObservedObject var updateManager = UpdateManager.shared

    private let labelWidth: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(l10n: "SETTINGS_TITLE")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: saveAndDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider().clawsy()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionSection
                    sharedFolderSection
                    responseChannelSection
                    hotkeysSection
                    toolsSection
                }
                .padding(20)
            }
        }
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .onAppear { loadActiveProfile() }
        .onChange(of: hostManager.activeHostId) { _ in loadActiveProfile() }
        .alert("Delete Host?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { hostToDelete = nil }
            Button("Delete", role: .destructive) {
                if let host = hostToDelete { hostManager.removeHost(id: host.id) }
                hostToDelete = nil
            }
        } message: {
            Text(NSLocalizedString("SETTINGS_DELETE_HOST_CONFIRM", bundle: .clawsy, comment: ""))
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                formRow("Name", text: $editedProfile.name)
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

                Divider().clawsy().padding(.vertical, 2)

                // SSH section — options are subordinate to SSH User
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

                Divider().clawsy().padding(.vertical, 2)

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

                if hostManager.profiles.count > 1 {
                    Divider().clawsy().padding(.vertical, 2)
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            hostToDelete = editedProfile
                            showDeleteConfirm = true
                        } label: {
                            Label(NSLocalizedString("DELETE_HOST_CONFIRM", bundle: .clawsy, comment: ""), systemImage: "trash")
                                .font(ClawsyTheme.Font.formLabel)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label(NSLocalizedString("SETTINGS_SECTION_CONNECTION", bundle: .clawsy, comment: ""), systemImage: ClawsyTheme.Icons.connection)
                .font(ClawsyTheme.Font.sectionHeader)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Shared Folder

    private var sharedFolderSection: some View {
        GroupBox {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.secondary.opacity(0.5))
                    .font(.system(size: 13))
                Text(editedProfile.sharedFolderPath.isEmpty ? "~/Documents/Clawsy" : editedProfile.sharedFolderPath)
                    .font(ClawsyTheme.Font.code)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(NSLocalizedString("SETTINGS_CHANGE_FOLDER", bundle: .clawsy, comment: "")) {
                    selectFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 2)
        } label: {
            Label(NSLocalizedString("SETTINGS_SECTION_SHARED_FOLDER", bundle: .clawsy, comment: ""), systemImage: ClawsyTheme.Icons.folder)
                .font(ClawsyTheme.Font.sectionHeader)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Response Channel

    private var responseChannelSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .foregroundColor(.accentColor)
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
            Label(NSLocalizedString("SETTINGS_SECTION_RESPONSE", bundle: .clawsy, comment: ""), systemImage: "arrowshape.turn.up.left.circle")
                .font(ClawsyTheme.Font.sectionHeader)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Hotkeys

    private var hotkeysSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("SETTINGS_HOTKEYS_HINT", bundle: .clawsy, comment: ""))
                    .font(ClawsyTheme.Font.caption)
                    .foregroundColor(.secondary)

                hotkeyRow("Quick Send", key: $quickSendHotkey)
                hotkeyRow("Clipboard", key: $pushClipboardHotkey)
                hotkeyRow("Camera", key: $cameraHotkey)
                hotkeyRow("Full Screenshot", key: $screenshotFullHotkey)
                hotkeyRow("Area Screenshot", key: $screenshotAreaHotkey)
            }
            .padding(.vertical, 2)
        } label: {
            Label(NSLocalizedString("SETTINGS_SECTION_HOTKEYS", bundle: .clawsy, comment: ""), systemImage: ClawsyTheme.Icons.hotkey)
                .font(ClawsyTheme.Font.sectionHeader)
                .foregroundColor(.secondary)
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
                    .frame(width: 28)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Tools & About

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Action rows — vertical, each on its own line
            HStack(spacing: 6) {
                Image(systemName: ClawsyTheme.Icons.debug)
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                Button(action: { onShowDebugLog?() }) {
                    Text(NSLocalizedString("DEBUG_LOG", bundle: .clawsy, comment: ""))
                        .font(ClawsyTheme.Font.formLabel)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Image(systemName: ClawsyTheme.Icons.update)
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                if updateManager.updateAvailable {
                    Button(action: { updateManager.downloadAndInstall() }) {
                        Text("Update: \(updateManager.updateVersion)")
                            .font(ClawsyTheme.Font.formLabel)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { updateManager.checkForUpdates(silent: false) }) {
                        Text(NSLocalizedString("SETTINGS_CHECK_UPDATES", bundle: .clawsy, comment: ""))
                            .font(ClawsyTheme.Font.formLabel)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: ClawsyTheme.Icons.repair)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .frame(width: 16)
                Button(action: { hostManager.repairActiveConnection() }) {
                    Text(NSLocalizedString("REPAIR_CONNECTION", bundle: .clawsy, comment: ""))
                        .font(ClawsyTheme.Font.formLabel)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            }

            // Version — right-aligned, subtle
            Text(SharedConfig.versionDisplay)
                .font(ClawsyTheme.Font.footer)
                .foregroundColor(.secondary.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 2)
        }
    }

    // MARK: - Helpers

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

    private func loadActiveProfile() {
        if let active = hostManager.activeProfile {
            editedProfile = active
        }
    }

    private func saveAndDismiss() {
        if editedProfile.name.trimmingCharacters(in: .whitespaces).isEmpty {
            editedProfile.name = editedProfile.gatewayHost
        }
        // Enforce SSH logic on save
        if editedProfile.sshUser.isEmpty {
            editedProfile.useSshFallback = false
            editedProfile.sshOnly = false
        }
        if !editedProfile.useSshFallback {
            editedProfile.sshOnly = false
        }
        hostManager.updateHost(editedProfile)
        isPresented = false
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
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
}
