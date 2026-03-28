import SwiftUI
import ClawsyShared

// MARK: - Onboarding Flow

/// Adaptive multi-page onboarding wizard.
/// Page order adapts to the connection scenario (setup code / Tailscale / manual).
/// Matches or exceeds the official OpenClaw Mac app's onboarding UX.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Binding var onboardingCompleted: Bool
    var onImportSetupCode: (String) -> Bool

    @State private var currentPage: OnboardingPage = .welcome
    @ObservedObject private var permissionMonitor = PermissionMonitor.shared
    @StateObject private var hostManager = HostManager()

    // Connection fields
    @State private var setupCode = ""
    @State private var setupCodeError = false
    @State private var connectMode: ConnectMode = .setupCode
    @State private var manualHost = ""
    @State private var manualPort = "18789"
    @State private var manualToken = ""
    @State private var manualSshUser = ""
    @State private var useSshFallback = true

    // Connection test
    @State private var connectionPhase: ConnectionTestPhase = .idle
    @State private var connectionError: String? = nil

    enum ConnectMode: String, CaseIterable {
        case setupCode = "Setup Code"
        case tailscale = "Tailscale"
        case manual = "Manual"
    }

    enum OnboardingPage: Int, CaseIterable {
        case welcome = 0
        case connect = 1
        case permissions = 2
        case ready = 3
    }

    enum ConnectionTestPhase {
        case idle, testing, success, failed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch currentPage {
                case .welcome: welcomePage
                case .connect: connectPage
                case .permissions: permissionsPage
                case .ready: readyPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.slide)

            Divider().clawsy()

            // Navigation
            HStack {
                // Page dots
                HStack(spacing: 6) {
                    ForEach(OnboardingPage.allCases, id: \.rawValue) { page in
                        Circle()
                            .fill(page == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                if currentPage != .welcome {
                    Button(NSLocalizedString("ONBOARDING_BACK", bundle: .clawsy, comment: "")) {
                        withAnimation { goBack() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Button(nextButtonTitle) {
                    withAnimation { goNext() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!canAdvance)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 460, height: 520)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "laptopcomputer.and.arrow.down")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text(l10n: "ONBOARDING_WELCOME_TITLE")
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(l10n: "ONBOARDING_WELCOME_DESC")
                    .font(ClawsyTheme.Font.menuItem)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            // Security note (like official app)
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(ClawsyTheme.Font.menuItem)
                    .foregroundColor(.green)
                Text(l10n: "ONBOARDING_SECURITY_NOTE")
                    .font(ClawsyTheme.Font.bannerBody)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.green.opacity(0.06))
            .cornerRadius(ClawsyTheme.Spacing.cornerRadius)
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Page 1: Connect

    private var connectPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(l10n: "ONBOARDING_CONNECT_TITLE")
                    .font(.system(size: 16, weight: .bold))

                // Mode picker
                Picker("", selection: $connectMode) {
                    Text(NSLocalizedString("ONBOARDING_MODE_SETUP_CODE", bundle: .clawsy, comment: "")).tag(ConnectMode.setupCode)
                    Text(NSLocalizedString("ONBOARDING_MODE_TAILSCALE", bundle: .clawsy, comment: "")).tag(ConnectMode.tailscale)
                    Text(NSLocalizedString("ONBOARDING_MODE_MANUAL", bundle: .clawsy, comment: "")).tag(ConnectMode.manual)
                }
                .pickerStyle(.segmented)

                switch connectMode {
                case .setupCode:
                    setupCodeSection

                case .tailscale:
                    tailscaleSection

                case .manual:
                    manualSection
                }

                // Connection test result
                if connectionPhase == .testing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(NSLocalizedString("ONBOARDING_CONNECTING", bundle: .clawsy, comment: "")).font(ClawsyTheme.Font.formLabel).foregroundColor(.secondary)
                    }
                } else if connectionPhase == .success {
                    Label(NSLocalizedString("ONBOARDING_CONNECTED", bundle: .clawsy, comment: ""), systemImage: "checkmark.circle.fill")
                        .font(ClawsyTheme.Font.sectionHeader)
                        .foregroundColor(.green)
                } else if connectionPhase == .failed, let error = connectionError {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Connection failed", systemImage: "xmark.circle.fill")
                            .font(ClawsyTheme.Font.sectionHeader)
                            .foregroundColor(.red)
                        Text(error)
                            .font(ClawsyTheme.Font.bannerBody)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }

    private var setupCodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n: "ONBOARDING_SETUP_CODE_HINT")
                .font(ClawsyTheme.Font.formLabel)
                .foregroundColor(.secondary)

            TextField("clawsy://pair?code=... or base64 code", text: $setupCode)
                .textFieldStyle(.roundedBorder)
                .font(ClawsyTheme.Font.code)

            if setupCodeError {
                Text(l10n: "ONBOARDING_SETUP_CODE_ERROR")
                    .font(ClawsyTheme.Font.bannerBody)
                    .foregroundColor(.red)
            }

            Button(NSLocalizedString("ONBOARDING_SETUP_CODE_BUTTON", bundle: .clawsy, comment: "")) {
                attemptSetupCode()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(setupCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var tailscaleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n: "ONBOARDING_TAILSCALE_HINT")
                .font(ClawsyTheme.Font.formLabel)
                .foregroundColor(.secondary)

            TextField("Tailscale hostname", text: $manualHost)
                .textFieldStyle(.roundedBorder)

            SecureField("Gateway Token", text: $manualToken)
                .textFieldStyle(.roundedBorder)

            Button(NSLocalizedString("ONBOARDING_TAILSCALE_BUTTON", bundle: .clawsy, comment: "")) {
                attemptManualConnect()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(manualHost.isEmpty || manualToken.isEmpty)
        }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n: "ONBOARDING_MANUAL_HINT")
                .font(ClawsyTheme.Font.formLabel)
                .foregroundColor(.secondary)

            TextField("Host", text: $manualHost)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Port", text: $manualPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Spacer()
            }
            SecureField("Gateway Token", text: $manualToken)
                .textFieldStyle(.roundedBorder)

            Divider().clawsy()

            TextField("SSH User (optional)", text: $manualSshUser)
                .textFieldStyle(.roundedBorder)
            Toggle("SSH Fallback", isOn: $useSshFallback)
                .font(ClawsyTheme.Font.formLabel)

            Button(NSLocalizedString("ONBOARDING_MANUAL_BUTTON", bundle: .clawsy, comment: "")) {
                attemptManualConnect()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(manualHost.isEmpty || manualToken.isEmpty)
        }
    }

    // MARK: - Page 2: Permissions

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l10n: "ONBOARDING_PERMISSIONS_TITLE")
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.top, 20)

            Text(l10n: "ONBOARDING_PERMISSIONS_DESC")
                .font(ClawsyTheme.Font.formLabel)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(ClawsyPermission.allCases) { perm in
                        PermissionRow(
                            permission: perm,
                            isGranted: permissionMonitor.status[perm] ?? false,
                            onRequest: { permissionMonitor.requestAndMonitor(perm) },
                            onOpenSettings: { permissionMonitor.openSettings(for: perm) }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }

            if permissionMonitor.allRequiredGranted {
                Label(NSLocalizedString("ONBOARDING_PERMISSIONS_ALL_GRANTED", bundle: .clawsy, comment: ""), systemImage: "checkmark.seal.fill")
                    .font(ClawsyTheme.Font.sectionHeader)
                    .foregroundColor(.green)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .onAppear { permissionMonitor.register() }
        .onDisappear { permissionMonitor.unregister() }
    }

    // MARK: - Page 3: Ready

    private var readyPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text(l10n: "ONBOARDING_READY_TITLE")
                .font(.system(size: 22, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                readyItem(icon: "menubar.rectangle", key: "ONBOARDING_READY_MENUBAR")
                readyItem(icon: "keyboard", key: "ONBOARDING_READY_QUICKSEND")
                readyItem(icon: "camera.viewfinder", key: "ONBOARDING_READY_SCREENSHOT")
                readyItem(icon: "folder", key: "ONBOARDING_READY_FOLDER")
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func readyItem(icon: String, key: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(ClawsyTheme.Font.menuItem)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(l10n: key)
                .font(ClawsyTheme.Font.formLabel)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Navigation

    private var nextButtonTitle: String {
        switch currentPage {
        case .welcome: return NSLocalizedString("ONBOARDING_LETS_GO", bundle: .clawsy, comment: "")
        case .connect, .permissions: return NSLocalizedString("ONBOARDING_NEXT", bundle: .clawsy, comment: "")
        case .ready: return NSLocalizedString("ONBOARDING_FINISH", bundle: .clawsy, comment: "")
        }
    }

    private var canAdvance: Bool {
        switch currentPage {
        case .welcome: return true
        case .connect: return connectionPhase == .success
        case .permissions: return true // permissions are optional to advance
        case .ready: return true
        }
    }

    private func goNext() {
        switch currentPage {
        case .welcome:
            currentPage = .connect
        case .connect:
            currentPage = .permissions
        case .permissions:
            currentPage = .ready
        case .ready:
            finish()
        }
    }

    private func goBack() {
        switch currentPage {
        case .connect: currentPage = .welcome
        case .permissions: currentPage = .connect
        case .ready: currentPage = .permissions
        default: break
        }
    }

    private func finish() {
        onboardingCompleted = true
        isPresented = false
    }

    // MARK: - Connection Attempts

    private func attemptSetupCode() {
        setupCodeError = false
        connectionPhase = .testing

        // Extract code from URL format if needed
        var code = setupCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.contains("code="), let url = URLComponents(string: code),
           let codeParam = url.queryItems?.first(where: { $0.name == "code" })?.value {
            code = codeParam
        }

        if onImportSetupCode(code) {
            connectionPhase = .success
        } else {
            connectionPhase = .failed
            connectionError = "Invalid setup code format."
            setupCodeError = true
        }
    }

    private func attemptManualConnect() {
        connectionPhase = .testing
        connectionError = nil

        let profile = HostProfile(
            name: manualHost.components(separatedBy: ".").first ?? manualHost,
            gatewayHost: manualHost,
            gatewayPort: manualPort.isEmpty ? "18789" : manualPort,
            serverToken: manualToken,
            sshUser: manualSshUser,
            useSshFallback: useSshFallback
        )

        hostManager.addHost(profile)
        hostManager.connectHost(profile.id)

        // Poll for connection success (max 15 seconds)
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            attempts += 1
            if hostManager.isConnected {
                timer.invalidate()
                connectionPhase = .success
            } else if attempts > 30 {
                timer.invalidate()
                connectionPhase = .failed
                if case .failed(let failure) = hostManager.state {
                    connectionError = failure.description
                } else {
                    connectionError = "Connection timed out after 15 seconds."
                }
            }
        }
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let permission: ClawsyPermission
    let isGranted: Bool
    var onRequest: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : permission.icon)
                .font(.system(size: 20))
                .foregroundColor(isGranted ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.displayName)
                    .font(ClawsyTheme.Font.sectionHeader)
                    .foregroundColor(.primary)
                Text(permission.description)
                    .font(ClawsyTheme.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !isGranted {
                Button(NSLocalizedString("PERM_BANNER_OPEN_SETTINGS", bundle: .clawsy, comment: "")) {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
