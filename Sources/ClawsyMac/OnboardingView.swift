import SwiftUI
import ClawsyShared

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Binding var onboardingCompleted: Bool

    /// Live gateway connection state (provided by AppDelegate)
    @Binding var isGatewayConnected: Bool

    /// Called when user pastes a setup code. Returns true on success.
    var onImportSetupCode: (String) -> Bool

    // MARK: - Local State
    @State private var setupCodeInput: String = ""
    @State private var setupCodeError: Bool = false
    @State private var setupCodeImported: Bool = false
    @State private var isConnecting: Bool = false

    @State private var isInApplications = false
    @State private var isAccessibilityGranted = false
    @State private var isFinderSyncRunning = false
    @State private var showFinderSyncHint = false
    @State private var isShareOnboarded = false

    @State private var refreshTimer: Timer?
    @State private var accessibilityJustRequested = false
    @State private var accessibilityUserConfirmed = false
    @State private var connectivityCheckTimer: Timer?

    private var isGatewayStep完了: Bool {
        isGatewayConnected || setupCodeImported
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
            // Header
            HStack(spacing: 14) {
                Image("OnboardingLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n: "ONBOARDING_TITLE")
                        .font(.system(size: 16, weight: .bold))
                    Text(l10n: "ONBOARDING_SUBTITLE")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider().opacity(0.3)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {

                    // ── Step 0: Gateway Connection (CRITICAL, FIRST) ──────────────────
                    GatewayConnectionStep(
                        isConnected: isGatewayConnected,
                        setupCodeInput: $setupCodeInput,
                        setupCodeError: $setupCodeError,
                        isConnecting: $isConnecting,
                        onConnect: connectWithSetupCode,
                        onOpenSettings: openSettings
                    )

                    // ── Step 1: App Location ──────────────────────────────────────────
                    OnboardingStepRow(
                        icon: "folder.fill",
                        title: NSLocalizedString("ONBOARDING_APP_LOCATION", bundle: .clawsy, comment: ""),
                        subtitle: NSLocalizedString("ONBOARDING_APP_LOCATION_DESC", bundle: .clawsy, comment: ""),
                        isCompleted: isInApplications,
                        isCritical: true,
                        actionLabel: NSLocalizedString("ONBOARDING_MOVE_TO_APPS", bundle: .clawsy, comment: ""),
                        action: moveToApplications
                    )

                    // ── Step 2: Accessibility ─────────────────────────────────────────
                    if isAccessibilityGranted {
                        OnboardingStepRow(
                            icon: "hand.raised.fill",
                            title: NSLocalizedString("ONBOARDING_ACCESSIBILITY", bundle: .clawsy, comment: ""),
                            subtitle: NSLocalizedString("ONBOARDING_ACCESSIBILITY_DESC", bundle: .clawsy, comment: ""),
                            isCompleted: true, isCritical: true, actionLabel: "", action: {}
                        )
                    } else if accessibilityJustRequested {
                        VStack(alignment: .leading, spacing: 6) {
                            OnboardingStepRow(
                                icon: "hand.raised.fill",
                                title: NSLocalizedString("ONBOARDING_ACCESSIBILITY", bundle: .clawsy, comment: ""),
                                subtitle: NSLocalizedString("ONBOARDING_ACCESSIBILITY_RESTART_HINT", bundle: .clawsy, comment: ""),
                                isCompleted: false, isCritical: true,
                                actionLabel: NSLocalizedString("ONBOARDING_RESTART", bundle: .clawsy, comment: ""),
                                action: restartApp
                            )
                            HStack {
                                Spacer()
                                Button(action: { accessibilityUserConfirmed = true }) {
                                    Text(l10n: "ONBOARDING_ACCESSIBILITY_SKIP_RESTART")
                                        .font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        OnboardingStepRow(
                            icon: "hand.raised.fill",
                            title: NSLocalizedString("ONBOARDING_ACCESSIBILITY", bundle: .clawsy, comment: ""),
                            subtitle: NSLocalizedString("ONBOARDING_ACCESSIBILITY_DESC", bundle: .clawsy, comment: ""),
                            isCompleted: false, isCritical: true,
                            actionLabel: NSLocalizedString("ONBOARDING_OPEN_SETTINGS", bundle: .clawsy, comment: ""),
                            action: requestAccessibility
                        )
                    }

                    // ── Step 3: FinderSync (optional) ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        OnboardingStepRow(
                            icon: "folder.badge.gearshape",
                            title: NSLocalizedString("ONBOARDING_FINDERSYNC", bundle: .clawsy, comment: ""),
                            subtitle: NSLocalizedString("ONBOARDING_FINDERSYNC_DESC", bundle: .clawsy, comment: ""),
                            isCompleted: isFinderSyncRunning, isCritical: false,
                            actionLabel: isFinderSyncRunning ? "" : NSLocalizedString("ONBOARDING_ENABLE", bundle: .clawsy, comment: ""),
                            action: enableFinderSync
                        )
                        if !isFinderSyncRunning && showFinderSyncHint {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill").font(.system(size: 11)).foregroundColor(.blue)
                                Text(NSLocalizedString("ONBOARDING_FINDERSYNC_HINT", bundle: .clawsy, comment: ""))
                                    .font(.system(size: 11)).foregroundColor(.blue)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.blue.opacity(0.08)).cornerRadius(6)
                        }
                    }

                    // ── Step 4: Share Extension (optional) ───────────────────────────
                    OnboardingStepRow(
                        icon: "square.and.arrow.up",
                        title: NSLocalizedString("ONBOARDING_SHARE", bundle: .clawsy, comment: ""),
                        subtitle: NSLocalizedString("ONBOARDING_SHARE_DESC", bundle: .clawsy, comment: ""),
                        isCompleted: isShareOnboarded, isCritical: false,
                        actionLabel: isShareOnboarded ? "" : NSLocalizedString("ONBOARDING_SHARE_ACTION", bundle: .clawsy, comment: ""),
                        action: acknowledgeShare
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            Spacer(minLength: 0)
            Divider().opacity(0.3)

            // Footer
            HStack {
                Button(action: { isPresented = false }) {
                    Text(l10n: "ONBOARDING_SKIP")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(action: { onboardingCompleted = true; isPresented = false }) {
                    Text(l10n: "ONBOARDING_DONE")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!criticalStepsCompleted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 440, height: 560)
        .onAppear {
            refreshStatus()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in refreshStatus() }
            // Watch for setup code imported via deep link
            NotificationCenter.default.addObserver(forName: NSNotification.Name("ClawsySetupCodeImported"),
                object: nil, queue: .main) { _ in
                setupCodeImported = true
                isConnecting = false
                setupCodeError = false
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    // MARK: - Gateway Connection

    private func connectWithSetupCode() {
        let code = setupCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isConnecting = true
        setupCodeError = false
        let success = onImportSetupCode(code)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !success {
                isConnecting = false
                setupCodeError = true
            }
            // If success: ClawsySetupCodeImported notification will clear isConnecting
        }
    }

    private func openSettings() {
        NotificationCenter.default.post(name: NSNotification.Name("ClawsyOpenSettings"), object: nil)
    }

    // MARK: - Status Checks

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
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run(); task.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            isFinderSyncRunning = output.contains("+")
        } catch { isFinderSyncRunning = false }
    }

    // MARK: - Actions

    private func moveToApplications() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Bundle.main.bundlePath)])
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        accessibilityPreviouslyRequested = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !AXIsProcessTrusted() { accessibilityJustRequested = true }
        }
    }

    private func restartApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }

    private func openFinderSyncSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]
        for urlString in urls {
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url); showFinderSyncHint = true; return }
        }
    }

    private func acknowledgeShare() {
        UserDefaults.standard.set(true, forKey: "clawsy_share_onboarded")
        isShareOnboarded = true
    }

    private func enableFinderSync() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-e", "use", "-i", "ai.clawsy.FinderSync"]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
        showFinderSyncHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            checkFinderSyncStatus()
            if !isFinderSyncRunning { openFinderSyncSettings() }
        }
    }
}

// MARK: - Agent Pair Tip (copyable "pair clawsy" message)

private struct AgentPairTip: View {
    @State private var copied = false
    private let pairMessage = "pair clawsy"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                Text(l10n: "ONBOARDING_GATEWAY_ASK_AGENT")
                    .font(.system(size: 11, weight: .medium))
            }

            Text(l10n: "ONBOARDING_GATEWAY_ASK_AGENT_DESC")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Copyable command pill
            Button(action: copyPairMessage) {
                HStack(spacing: 6) {
                    Text(pairMessage)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.accentColor)
                    Spacer()
                    Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 10))
                        .foregroundColor(copied ? .green : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(8)
    }

    private func copyPairMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairMessage, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

// MARK: - Gateway Connection Step

private struct GatewayConnectionStep: View {
    let isConnected: Bool
    @Binding var setupCodeInput: String
    @Binding var setupCodeError: Bool
    @Binding var isConnecting: Bool
    var onConnect: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 12) {
                Image(systemName: isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isConnected ? .green : .orange)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n: "ONBOARDING_GATEWAY_TITLE")
                        .font(.system(size: 13, weight: .medium))
                    Text(l10n: isConnected ? "ONBOARDING_GATEWAY_CONNECTED" : "ONBOARDING_GATEWAY_DESC")
                        .font(.system(size: 11))
                        .foregroundColor(isConnected ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if !isConnected {
                // Ask-your-agent tip with copyable command
                AgentPairTip()

                // Setup code paste field
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        if setupCodeInput.isEmpty {
                            Text(l10n: "ONBOARDING_GATEWAY_CODE_PLACEHOLDER")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.leading, 7)
                        }
                        TextField("", text: $setupCodeInput)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .onSubmit { onConnect() }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(setupCodeError ? Color.red : Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                    Button(action: onConnect) {
                        if isConnecting {
                            ProgressView().controlSize(.small).frame(width: 40)
                        } else {
                            Text(l10n: "ONBOARDING_GATEWAY_CONNECT")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(setupCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
                }

                if setupCodeError {
                    Text(l10n: "ONBOARDING_GATEWAY_CODE_ERROR")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }

                // Manual fallback
                HStack {
                    Spacer()
                    Button(action: onOpenSettings) {
                        Text(l10n: "ONBOARDING_GATEWAY_MANUAL")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isConnected ? Color.green.opacity(0.06) : Color.orange.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isConnected ? Color.green.opacity(0.3) : Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Step Row

private struct OnboardingStepRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isCompleted: Bool
    let isCritical: Bool
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCompleted
                  ? "checkmark.circle.fill"
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
