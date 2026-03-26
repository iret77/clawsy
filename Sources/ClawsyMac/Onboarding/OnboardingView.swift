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
    @StateObject private var permissionMonitor = PermissionMonitor()
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

            Divider().opacity(0.3)

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
                    Button("Back") {
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
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "laptopcomputer.and.arrow.down")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Give your AI agent\neyes and hands on your Mac")
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Clawsy connects your OpenClaw agents to your Mac — screenshots, clipboard, files, and camera — with full control over what's shared.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            // Security note (like official app)
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                Text("Your data stays between your Mac and your OpenClaw server. No cloud, no tracking.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.green.opacity(0.06))
            .cornerRadius(8)
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Page 1: Connect

    private var connectPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connect to your OpenClaw server")
                    .font(.system(size: 16, weight: .bold))

                // Mode picker
                Picker("", selection: $connectMode) {
                    ForEach(ConnectMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
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
                        Text("Connecting...").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                } else if connectionPhase == .success {
                    Label("Connected!", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                } else if connectionPhase == .failed, let error = connectionError {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Connection failed", systemImage: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }

    private var setupCodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste the setup code from your OpenClaw agent or admin:")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            TextField("clawsy://pair?code=... or base64 code", text: $setupCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            if setupCodeError {
                Text("Invalid setup code. Please check and try again.")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            Button("Connect with Setup Code") {
                attemptSetupCode()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(setupCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var tailscaleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your Tailscale hostname (e.g. agenthost.tailnet-name.ts.net):")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            TextField("Tailscale hostname", text: $manualHost)
                .textFieldStyle(.roundedBorder)

            SecureField("Gateway Token", text: $manualToken)
                .textFieldStyle(.roundedBorder)

            Button("Connect via Tailscale") {
                attemptManualConnect()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(manualHost.isEmpty || manualToken.isEmpty)
        }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your gateway connection details:")
                .font(.system(size: 12))
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

            Divider().opacity(0.2)

            TextField("SSH User (optional)", text: $manualSshUser)
                .textFieldStyle(.roundedBorder)
            Toggle("SSH Fallback", isOn: $useSshFallback)
                .font(.system(size: 12))

            Button("Test Connection") {
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
            Text("Permissions")
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.top, 20)

            Text("Clawsy needs a few macOS permissions to work. Grant them below — you can change these anytime in System Settings.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(ClawsyPermission.allCases) { perm in
                        PermissionRow(
                            permission: perm,
                            isGranted: permissionMonitor.status[perm] ?? false,
                            onRequest: { permissionMonitor.requestPermission(perm) },
                            onOpenSettings: { permissionMonitor.openSettings(for: perm) }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }

            if permissionMonitor.allRequiredGranted {
                Label("All required permissions granted!", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .onAppear { permissionMonitor.startPolling() }
        .onDisappear { permissionMonitor.stopPolling() }
    }

    // MARK: - Page 3: Ready

    private var readyPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("You're all set!")
                .font(.system(size: 22, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                readyItem(icon: "menubar.rectangle", text: "Clawsy lives in your menu bar — click the icon anytime")
                readyItem(icon: "keyboard", text: "Use ⌘⇧K for Quick Send from anywhere")
                readyItem(icon: "camera.viewfinder", text: "Use ⌘⇧S for instant screenshot to agent")
                readyItem(icon: "folder", text: "Share files via the Clawsy folder in Finder")
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func readyItem(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Navigation

    private var nextButtonTitle: String {
        switch currentPage {
        case .welcome: return "Let's go"
        case .connect: return "Next"
        case .permissions: return "Next"
        case .ready: return "Finish"
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
            Image(systemName: permission.icon)
                .font(.system(size: 16))
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(permission.rawValue)
                        .font(.system(size: 12, weight: .medium))
                    if permission.isRequired {
                        Text("Required")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(3)
                    }
                }
                Text(permission.description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 18))
            } else {
                Button("Grant") { onRequest() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button(action: onOpenSettings) {
                    Image(systemName: "gear")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open System Settings")
            }
        }
        .padding(10)
        .background(Color.primary.opacity(isGranted ? 0.02 : 0.04))
        .cornerRadius(8)
    }
}
