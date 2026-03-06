import SwiftUI
import ClawsyShared

// MARK: - Main Onboarding View

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Binding var onboardingCompleted: Bool
    @Binding var isGatewayConnected: Bool
    var onImportSetupCode: (String) -> Bool

    // ── State ──────────────────────────────────────────────────────────────
    @State private var isInApplications = false
    @State private var isAccessibilityGranted = false
    @State private var isFinderSyncRunning = false
    @State private var showFinderSyncHint = false
    @State private var isShareOnboarded = false
    @State private var refreshTimer: Timer?
    @State private var accessibilityJustRequested = false
    @State private var accessibilityUserConfirmed = false

    // Gateway step
    @State private var gatewayPhase: GatewayPhase = .installPrompt
    @State private var setupCodeInput: String = ""
    @State private var setupCodeError: Bool = false
    @State private var isConnecting: Bool = false
    @State private var promptCopied: Bool = false

    enum GatewayPhase {
        case installPrompt   // fresh install — show the "send this to your agent" prompt
        case waitingForLink  // user sent the prompt, waiting for agent to respond with link
        case pasteCode       // manual fallback — paste setup code directly
        case connected       // done ✅
    }

    private var criticalStepsCompleted: Bool {
        isGatewayConnected &&
        isInApplications &&
        (isAccessibilityGranted || accessibilityUserConfirmed)
    }

    private var accessibilityPreviouslyRequested: Bool {
        get { UserDefaults.standard.bool(forKey: "clawsy_accessibility_requested") }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "clawsy_accessibility_requested") }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 14) {
                Image("OnboardingLogo")
                    .resizable().scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n: "ONBOARDING_TITLE").font(.system(size: 16, weight: .bold))
                    Text(l10n: "ONBOARDING_SUBTITLE").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)

            Divider().opacity(0.3)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {

                    // ── Step 0: Gateway ───────────────────────────────────
                    GatewayStep(
                        phase: $gatewayPhase,
                        isConnected: isGatewayConnected,
                        setupCodeInput: $setupCodeInput,
                        setupCodeError: $setupCodeError,
                        isConnecting: $isConnecting,
                        promptCopied: $promptCopied,
                        onConnect: connectWithSetupCode,
                        onOpenSettings: openSettings
                    )

                    // ── Step 1: App Location ──────────────────────────────
                    OnboardingStepRow(
                        icon: "folder.fill",
                        title: l10n("ONBOARDING_APP_LOCATION"),
                        subtitle: l10n("ONBOARDING_APP_LOCATION_DESC"),
                        isCompleted: isInApplications, isCritical: true,
                        actionLabel: l10n("ONBOARDING_MOVE_TO_APPS"),
                        action: moveToApplications
                    )

                    // ── Step 2: Accessibility ─────────────────────────────
                    if isAccessibilityGranted {
                        OnboardingStepRow(icon: "hand.raised.fill",
                            title: l10n("ONBOARDING_ACCESSIBILITY"),
                            subtitle: l10n("ONBOARDING_ACCESSIBILITY_DESC"),
                            isCompleted: true, isCritical: true, actionLabel: "", action: {})
                    } else if accessibilityJustRequested {
                        VStack(alignment: .leading, spacing: 6) {
                            OnboardingStepRow(icon: "hand.raised.fill",
                                title: l10n("ONBOARDING_ACCESSIBILITY"),
                                subtitle: l10n("ONBOARDING_ACCESSIBILITY_RESTART_HINT"),
                                isCompleted: false, isCritical: true,
                                actionLabel: l10n("ONBOARDING_RESTART"), action: restartApp)
                            HStack {
                                Spacer()
                                Button(action: { accessibilityUserConfirmed = true }) {
                                    Text(l10n: "ONBOARDING_ACCESSIBILITY_SKIP_RESTART")
                                        .font(.system(size: 10)).foregroundColor(.secondary)
                                }.buttonStyle(.plain)
                            }
                        }
                    } else {
                        OnboardingStepRow(icon: "hand.raised.fill",
                            title: l10n("ONBOARDING_ACCESSIBILITY"),
                            subtitle: l10n("ONBOARDING_ACCESSIBILITY_DESC"),
                            isCompleted: false, isCritical: true,
                            actionLabel: l10n("ONBOARDING_OPEN_SETTINGS"), action: requestAccessibility)
                    }

                    // ── Step 3: FinderSync (optional) ─────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        OnboardingStepRow(icon: "folder.badge.gearshape",
                            title: l10n("ONBOARDING_FINDERSYNC"),
                            subtitle: l10n("ONBOARDING_FINDERSYNC_DESC"),
                            isCompleted: isFinderSyncRunning, isCritical: false,
                            actionLabel: isFinderSyncRunning ? "" : l10n("ONBOARDING_ENABLE"),
                            action: enableFinderSync)
                        if !isFinderSyncRunning && showFinderSyncHint {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill").font(.system(size: 11)).foregroundColor(.blue)
                                Text(l10n("ONBOARDING_FINDERSYNC_HINT")).font(.system(size: 11)).foregroundColor(.blue)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.blue.opacity(0.08)).cornerRadius(6)
                        }
                    }

                    // ── Step 4: Share Extension (optional) ────────────────
                    OnboardingStepRow(icon: "square.and.arrow.up",
                        title: l10n("ONBOARDING_SHARE"),
                        subtitle: l10n("ONBOARDING_SHARE_DESC"),
                        isCompleted: isShareOnboarded, isCritical: false,
                        actionLabel: isShareOnboarded ? "" : l10n("ONBOARDING_SHARE_ACTION"),
                        action: acknowledgeShare)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            }

            Spacer(minLength: 0)
            Divider().opacity(0.3)

            // ── Footer ────────────────────────────────────────────────────
            HStack {
                Button(action: { isPresented = false }) { Text(l10n: "ONBOARDING_SKIP") }
                    .buttonStyle(.bordered)
                Spacer()
                Button(action: { onboardingCompleted = true; isPresented = false }) {
                    Text(l10n: "ONBOARDING_DONE")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!criticalStepsCompleted)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 460, height: 590)
        .onAppear {
            // If already connected (e.g. re-opened), skip to connected phase
            if isGatewayConnected { gatewayPhase = .connected }
            refreshStatus()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in refreshStatus() }
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ClawsySetupCodeImported"), object: nil, queue: .main) { _ in
                isConnecting = false
                gatewayPhase = .connected
            }
        }
        .onDisappear { refreshTimer?.invalidate(); refreshTimer = nil }
        .onChange(of: isGatewayConnected) { connected in
            if connected { gatewayPhase = .connected }
        }
    }

    // ── Gateway Connect ───────────────────────────────────────────────────
    private func connectWithSetupCode() {
        let code = setupCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isConnecting = true; setupCodeError = false
        let success = onImportSetupCode(code)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !success { isConnecting = false; setupCodeError = true }
        }
    }

    private func openSettings() {
        NotificationCenter.default.post(name: NSNotification.Name("ClawsyOpenSettings"), object: nil)
    }

    // ── Helpers ───────────────────────────────────────────────────────────
    private func l10n(_ key: String) -> String {
        NSLocalizedString(key, bundle: .clawsy, comment: "")
    }

    // ── Status Refresh ────────────────────────────────────────────────────
    private func refreshStatus() {
        isInApplications = Bundle.main.bundlePath.hasPrefix("/Applications")
        let trusted = AXIsProcessTrusted()
        isAccessibilityGranted = trusted
        if trusted { accessibilityJustRequested = false; accessibilityPreviouslyRequested = true }
        checkFinderSyncStatus()
        isShareOnboarded = UserDefaults.standard.bool(forKey: "clawsy_share_onboarded")
    }

    private func checkFinderSyncStatus() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-m", "-i", "ai.clawsy.FinderSync"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            isFinderSyncRunning = out.contains("+")
        } catch { isFinderSyncRunning = false }
    }

    // ── Actions ───────────────────────────────────────────────────────────
    private func moveToApplications() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Bundle.main.bundlePath)])
    }
    private func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        accessibilityPreviouslyRequested = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !AXIsProcessTrusted() { accessibilityJustRequested = true }
        }
    }
    private func restartApp() {
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = ["-n", Bundle.main.bundlePath]
        t.standardOutput = FileHandle.nullDevice; t.standardError = FileHandle.nullDevice
        try? t.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
    private func openFinderSyncSettings() {
        let urls = ["x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
                    "x-apple.systempreferences:com.apple.ExtensionsPreferences"]
        for s in urls { if let u = URL(string: s) { NSWorkspace.shared.open(u); showFinderSyncHint = true; return } }
    }
    private func acknowledgeShare() {
        UserDefaults.standard.set(true, forKey: "clawsy_share_onboarded"); isShareOnboarded = true
    }
    private func enableFinderSync() {
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        t.arguments = ["-e", "use", "-i", "ai.clawsy.FinderSync"]
        t.standardOutput = FileHandle.nullDevice; t.standardError = FileHandle.nullDevice
        try? t.run(); t.waitUntilExit()
        showFinderSyncHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            checkFinderSyncStatus()
            if !isFinderSyncRunning { openFinderSyncSettings() }
        }
    }
}

// MARK: - Gateway Step (the heart of onboarding)

private struct GatewayStep: View {
    @Binding var phase: OnboardingView.GatewayPhase
    let isConnected: Bool
    @Binding var setupCodeInput: String
    @Binding var setupCodeError: Bool
    @Binding var isConnecting: Bool
    @Binding var promptCopied: Bool
    var onConnect: () -> Void
    var onOpenSettings: () -> Void

    // The exact install command — one-liner the agent can execute
    private let installCommand = "curl -fsSL https://raw.githubusercontent.com/iret77/clawsy/main/server/install.sh | bash"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Header row ────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 20))
                    .foregroundColor(statusColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n: "ONBOARDING_GATEWAY_TITLE")
                        .font(.system(size: 13, weight: .medium))
                    Text(statusSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(isConnected ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if phase == .installPrompt || phase == .waitingForLink {
                    Button(phase == .waitingForLink ? l10n("ONBOARDING_GATEWAY_HAVE_CODE") : "") {
                        phase = .pasteCode
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                }
            }

            // ── Phase: Install Prompt ─────────────────────────────────────
            if phase == .installPrompt {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n: "ONBOARDING_INSTALL_STEP1")
                        .font(.system(size: 11, weight: .medium))

                    // Copyable install command
                    Button(action: copyInstallCommand) {
                        HStack(spacing: 8) {
                            Text(installCommand)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.85))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Image(systemName: promptCopied ? "checkmark" : "doc.on.clipboard")
                                .font(.system(size: 11))
                                .foregroundColor(promptCopied ? .green : .secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Text(l10n: "ONBOARDING_INSTALL_STEP2")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    // "I sent it" → show waiting state
                    Button(action: { phase = .waitingForLink }) {
                        Label(l10n("ONBOARDING_INSTALL_SENT"), systemImage: "arrow.up.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // ── Phase: Waiting for link ───────────────────────────────────
            if phase == .waitingForLink {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(l10n: "ONBOARDING_INSTALL_WAITING")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                Text(l10n: "ONBOARDING_INSTALL_WAITING_HINT")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }

            // ── Phase: Paste Code (manual fallback) ───────────────────────
            if phase == .pasteCode {
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        if setupCodeInput.isEmpty {
                            Text(l10n: "ONBOARDING_GATEWAY_CODE_PLACEHOLDER")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.leading, 7)
                        }
                        TextField("", text: $setupCodeInput)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .onSubmit { onConnect() }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(setupCodeError ? Color.red : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    Button(action: onConnect) {
                        if isConnecting { ProgressView().controlSize(.small).frame(width: 44) }
                        else { Text(l10n: "ONBOARDING_GATEWAY_CONNECT").font(.system(size: 11, weight: .medium)) }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(setupCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
                }
                if setupCodeError {
                    Text(l10n: "ONBOARDING_GATEWAY_CODE_ERROR").font(.system(size: 10)).foregroundColor(.red)
                }
                HStack {
                    Button(action: { phase = .installPrompt }) {
                        Text(l10n: "ONBOARDING_INSTALL_BACK").font(.system(size: 10)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                    Spacer()
                    Button(action: onOpenSettings) {
                        Text(l10n: "ONBOARDING_GATEWAY_MANUAL").font(.system(size: 10)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(isConnected ? Color.green.opacity(0.06) : Color.orange.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isConnected ? Color.green.opacity(0.3) : Color.orange.opacity(0.2), lineWidth: 1))
    }

    private var statusIcon: String {
        switch phase {
        case .connected: return "checkmark.circle.fill"
        case .waitingForLink: return "clock.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }
    private var statusColor: Color {
        switch phase {
        case .connected: return .green
        case .waitingForLink: return .blue
        default: return .orange
        }
    }
    private var statusSubtitle: String {
        switch phase {
        case .connected:      return NSLocalizedString("ONBOARDING_GATEWAY_CONNECTED", bundle: .clawsy, comment: "")
        case .waitingForLink: return NSLocalizedString("ONBOARDING_INSTALL_WAITING", bundle: .clawsy, comment: "")
        case .pasteCode:      return NSLocalizedString("ONBOARDING_GATEWAY_DESC", bundle: .clawsy, comment: "")
        case .installPrompt:  return NSLocalizedString("ONBOARDING_INSTALL_SUBTITLE", bundle: .clawsy, comment: "")
        }
    }

    private func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(installCommand, forType: .string)
        promptCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { promptCopied = false }
    }
}

// MARK: - Generic Step Row

private struct OnboardingStepRow: View {
    let icon: String; let title: String; let subtitle: String
    let isCompleted: Bool; let isCritical: Bool
    let actionLabel: String; let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCompleted ? "checkmark.circle.fill"
                                          : (isCritical ? "exclamationmark.triangle.fill" : "circle.dashed"))
                .font(.system(size: 20))
                .foregroundColor(isCompleted ? .green : (isCritical ? .orange : .secondary))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if !isCritical {
                        Text(l10n: "ONBOARDING_OPTIONAL")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1)).cornerRadius(3)
                    }
                }
                Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !isCompleted && !actionLabel.isEmpty {
                Button(action: action) { Text(actionLabel).font(.system(size: 11)) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }
}
