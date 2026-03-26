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

    // Global hotkey settings
    @AppStorage("quickSendHotkey", store: SharedConfig.sharedDefaults) private var quickSendHotkey = "K"
    @AppStorage("pushClipboardHotkey", store: SharedConfig.sharedDefaults) private var pushClipboardHotkey = "V"
    @AppStorage("cameraHotkey", store: SharedConfig.sharedDefaults) private var cameraHotkey = "P"
    @AppStorage("screenshotFullHotkey", store: SharedConfig.sharedDefaults) private var screenshotFullHotkey = "S"
    @AppStorage("screenshotAreaHotkey", store: SharedConfig.sharedDefaults) private var screenshotAreaHotkey = "A"

    @ObservedObject var updateManager = UpdateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(l10n: "SETTINGS_TITLE")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: saveAndDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Host Settings
                    connectionSection
                    Divider().opacity(0.3)

                    // Shared Folder
                    sharedFolderSection
                    Divider().opacity(0.3)

                    // Hotkeys
                    hotkeysSection
                    Divider().opacity(0.3)

                    // Tools
                    toolsSection
                }
                .padding(20)
            }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Label(NSLocalizedString("SETTINGS_SECTION_CONNECTION", bundle: .clawsy, comment: ""), systemImage: "network")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            LabeledContent("Name") {
                TextField("", text: $editedProfile.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }
            LabeledContent("Host") {
                TextField("", text: $editedProfile.gatewayHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }
            LabeledContent("Port") {
                TextField("", text: $editedProfile.gatewayPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
            }
            LabeledContent("Token") {
                SecureField("", text: $editedProfile.serverToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }

            Divider().opacity(0.3)

            LabeledContent("SSH User") {
                TextField("", text: $editedProfile.sshUser)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
            }
            Toggle("SSH Fallback", isOn: $editedProfile.useSshFallback)
                .font(.system(size: 12))
            Toggle("SSH Only", isOn: $editedProfile.sshOnly)
                .font(.system(size: 12))

            if hostManager.profiles.count > 1 {
                Button(role: .destructive) {
                    hostToDelete = editedProfile
                    showDeleteConfirm = true
                } label: {
                    Label("Remove Host", systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Shared Folder

    private var sharedFolderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(NSLocalizedString("SETTINGS_SECTION_SHARED_FOLDER", bundle: .clawsy, comment: ""), systemImage: "folder")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            HStack {
                Text(editedProfile.sharedFolderPath.isEmpty ? "~/Documents/Clawsy" : editedProfile.sharedFolderPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(NSLocalizedString("SETTINGS_CHANGE_FOLDER", bundle: .clawsy, comment: "")) { selectFolder() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Hotkeys

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(NSLocalizedString("SETTINGS_SECTION_HOTKEYS", bundle: .clawsy, comment: ""), systemImage: "keyboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Text(NSLocalizedString("SETTINGS_HOTKEYS_HINT", bundle: .clawsy, comment: ""))
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            hotkeyRow("Quick Send", key: $quickSendHotkey)
            hotkeyRow("Clipboard", key: $pushClipboardHotkey)
            hotkeyRow("Camera", key: $cameraHotkey)
            hotkeyRow("Full Screenshot", key: $screenshotFullHotkey)
            hotkeyRow("Area Screenshot", key: $screenshotAreaHotkey)
        }
    }

    private func hotkeyRow(_ label: String, key: Binding<String>) -> some View {
        HStack {
            Text(label).font(.system(size: 11))
            Spacer()
            Text("⌘⇧").font(.system(size: 10)).foregroundColor(.secondary)
            TextField("", text: key)
                .textFieldStyle(.roundedBorder)
                .frame(width: 30)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Tools

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("SETTINGS_SECTION_TOOLS", bundle: .clawsy, comment: ""), systemImage: "wrench.and.screwdriver")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Button(action: { onShowDebugLog?() }) {
                Label(NSLocalizedString("DEBUG_LOG", bundle: .clawsy, comment: ""), systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if updateManager.updateAvailable {
                Button(action: { updateManager.downloadAndInstall() }) {
                    Label("Update Available: \(updateManager.updateVersion)", systemImage: "arrow.down.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button(action: { updateManager.checkForUpdates(silent: false) }) {
                    Label(NSLocalizedString("SETTINGS_CHECK_UPDATES", bundle: .clawsy, comment: ""), systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Version footer
            Text(SharedConfig.versionDisplay)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
    }

    // MARK: - Helpers

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
                editedProfile.sharedFolderPath = path
            }
        }
    }
}
