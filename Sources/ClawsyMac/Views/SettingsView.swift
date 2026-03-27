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
    @State private var showingAddHost = false
    @State private var hostToDelete: HostProfile? = nil
    @State private var showDeleteConfirm = false

    @AppStorage("quickSendHotkey", store: SharedConfig.sharedDefaults) private var quickSendHotkey = "K"
    @AppStorage("pushClipboardHotkey", store: SharedConfig.sharedDefaults) private var pushClipboardHotkey = "V"
    @AppStorage("cameraHotkey", store: SharedConfig.sharedDefaults) private var cameraHotkey = "P"
    @AppStorage("screenshotFullHotkey", store: SharedConfig.sharedDefaults) private var screenshotFullHotkey = "S"
    @AppStorage("screenshotAreaHotkey", store: SharedConfig.sharedDefaults) private var screenshotAreaHotkey = "A"

    @ObservedObject var updateManager = UpdateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — matches System Settings style
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
                VStack(alignment: .leading, spacing: 20) {
                    connectionSection
                    sharedFolderSection
                    hotkeysSection
                    toolsSection
                }
                .padding(20)
            }
        }
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .onAppear { loadActiveProfile() }
        .onChange(of: hostManager.activeHostId) { _ in loadActiveProfile() }
        .sheet(isPresented: $showingAddHost) {
            AddHostSheet(hostManager: hostManager, isPresented: $showingAddHost, onHostAdded: onHostAdded)
        }
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
                formRow("Port", text: $editedProfile.gatewayPort, width: 80)
                HStack {
                    Text("Token").font(ClawsyTheme.Font.formLabel).frame(width: 70, alignment: .trailing)
                    SecureField("", text: $editedProfile.serverToken)
                        .textFieldStyle(.roundedBorder)
                        .font(ClawsyTheme.Font.formValue)
                }

                Divider().clawsy().padding(.vertical, 4)

                formRow("SSH User", text: $editedProfile.sshUser, width: 120)
                Toggle(isOn: $editedProfile.useSshFallback) {
                    Text("SSH Fallback").font(ClawsyTheme.Font.formLabel)
                }
                .toggleStyle(.checkbox)
                Toggle(isOn: $editedProfile.sshOnly) {
                    Text("SSH Only").font(ClawsyTheme.Font.formLabel)
                }
                .toggleStyle(.checkbox)

                if hostManager.profiles.count > 1 {
                    Divider().clawsy().padding(.vertical, 2)
                    Button(role: .destructive) {
                        hostToDelete = editedProfile
                        showDeleteConfirm = true
                    } label: {
                        Label("Remove Host", systemImage: "trash")
                            .font(ClawsyTheme.Font.formLabel)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
            HStack {
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

    // MARK: - Tools

    private var toolsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                // Debug Log
                settingsRow(icon: ClawsyTheme.Icons.debug, label: NSLocalizedString("DEBUG_LOG", bundle: .clawsy, comment: "")) {
                    onShowDebugLog?()
                }

                Divider().clawsy()

                // Updates
                if updateManager.updateAvailable {
                    settingsRow(icon: "arrow.down.circle.fill", label: "Update: \(updateManager.updateVersion)", tint: .accentColor) {
                        updateManager.downloadAndInstall()
                    }
                } else {
                    settingsRow(icon: ClawsyTheme.Icons.update, label: NSLocalizedString("SETTINGS_CHECK_UPDATES", bundle: .clawsy, comment: "")) {
                        updateManager.checkForUpdates(silent: false)
                    }
                }

                Divider().clawsy()

                // Re-Pair
                settingsRow(icon: ClawsyTheme.Icons.repair, label: NSLocalizedString("REPAIR_CONNECTION", bundle: .clawsy, comment: ""), tint: .orange) {
                    hostManager.repairActiveConnection()
                }
            }

            // Version
            Text(SharedConfig.versionDisplay)
                .font(ClawsyTheme.Font.footer)
                .foregroundColor(.secondary.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 6)
        } label: {
            Label(NSLocalizedString("SETTINGS_SECTION_TOOLS", bundle: .clawsy, comment: ""), systemImage: ClawsyTheme.Icons.tools)
                .font(ClawsyTheme.Font.sectionHeader)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func settingsRow(icon: String, label: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(tint)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(ClawsyTheme.Font.formLabel)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.3))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formRow(_ label: String, text: Binding<String>, width: CGFloat = 180) -> some View {
        HStack {
            Text(label).font(ClawsyTheme.Font.formLabel).frame(width: 70, alignment: .trailing)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(ClawsyTheme.Font.formValue)
                .frame(maxWidth: width)
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
