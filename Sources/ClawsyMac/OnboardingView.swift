import SwiftUI
import ClawsyShared

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Binding var onboardingCompleted: Bool

    @State private var isInApplications = false
    @State private var isAccessibilityGranted = false
    @State private var isFinderSyncRunning = false
    @State private var showFinderSyncHint = false
    @State private var isShareOnboarded = false
    @State private var isServerSetupDone: Bool = UserDefaults.standard.bool(forKey: "clawsy_server_setup_done")
    @State private var refreshTimer: Timer?
    @State private var accessibilityJustRequested = false
    @State private var accessibilityUserConfirmed = false

    private var criticalStepsCompleted: Bool {
        isInApplications && (isAccessibilityGranted || accessibilityUserConfirmed)
    }

    /// True if accessibility was previously requested (persisted across launches)
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

            // Checklist (scrollable as safety net)
            ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                // Step 1: App Location
                OnboardingStepRow(
                    icon: "folder.fill",
                    title: NSLocalizedString("ONBOARDING_APP_LOCATION", bundle: .clawsy, comment: ""),
                    subtitle: NSLocalizedString("ONBOARDING_APP_LOCATION_DESC", bundle: .clawsy, comment: ""),
                    isCompleted: isInApplications,
                    isCritical: true,
                    actionLabel: NSLocalizedString("ONBOARDING_MOVE_TO_APPS", bundle: .clawsy, comment: ""),
                    action: moveToApplications
                )

                // Step 2: Accessibility
                if isAccessibilityGranted {
                    OnboardingStepRow(
                        icon: "hand.raised.fill",
                        title: NSLocalizedString("ONBOARDING_ACCESSIBILITY", bundle: .clawsy, comment: ""),
                        subtitle: NSLocalizedString("ONBOARDING_ACCESSIBILITY_DESC", bundle: .clawsy, comment: ""),
                        isCompleted: true,
                        isCritical: true,
                        actionLabel: "",
                        action: {}
                    )
                } else if accessibilityJustRequested {
                    // After granting: show restart button + "skip restart" option
                    VStack(alignment: .leading, spacing: 6) {
                        OnboardingStepRow(
                            icon: "hand.raised.fill",
                            title: NSLocalizedString("ONBOARDING_ACCESSIBILITY", bundle: .clawsy, comment: ""),
                            subtitle: NSLocalizedString("ONBOARDING_ACCESSIBILITY_RESTART_HINT", bundle: .clawsy, comment: ""),
                            isCompleted: false,
                            isCritical: true,
                            actionLabel: NSLocalizedString("ONBOARDING_RESTART", bundle: .clawsy, comment: ""),
                            action: restartApp
                        )
                        HStack {
                            Spacer()
                            Button(action: { accessibilityUserConfirmed = true }) {
                                Text(l10n: "ONBOARDING_ACCESSIBILITY_SKIP_RESTART")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, 0)
                    }
                } else {
                    OnboardingStepRow(
                        icon: "hand.raised.fill",
                        title: NSLocalizedString("ONBOARDING_ACCESSIBILITY", bundle: .clawsy, comment: ""),
                        subtitle: NSLocalizedString("ONBOARDING_ACCESSIBILITY_DESC", bundle: .clawsy, comment: ""),
                        isCompleted: false,
                        isCritical: true,
                        actionLabel: NSLocalizedString("ONBOARDING_OPEN_SETTINGS", bundle: .clawsy, comment: ""),
                        action: requestAccessibility
                    )
                }

                // Step 3: FinderSync (optional)
                VStack(alignment: .leading, spacing: 6) {
                    OnboardingStepRow(
                        icon: "folder.badge.gearshape",
                        title: NSLocalizedString("ONBOARDING_FINDERSYNC", bundle: .clawsy, comment: ""),
                        subtitle: NSLocalizedString("ONBOARDING_FINDERSYNC_DESC", bundle: .clawsy, comment: ""),
                        isCompleted: isFinderSyncRunning,
                        isCritical: false,
                        actionLabel: isFinderSyncRunning ? "" : NSLocalizedString("ONBOARDING_ENABLE", bundle: .clawsy, comment: ""),
                        action: enableFinderSync
                    )
                    if !isFinderSyncRunning && showFinderSyncHint {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                            Text(NSLocalizedString("ONBOARDING_FINDERSYNC_HINT", bundle: .clawsy, comment: ""))
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(6)
                    }
                }

                // Step 4: Share Extension (optional)
                OnboardingStepRow(
                    icon: "square.and.arrow.up",
                    title: NSLocalizedString("ONBOARDING_SHARE", bundle: .clawsy, comment: ""),
                    subtitle: NSLocalizedString("ONBOARDING_SHARE_DESC", bundle: .clawsy, comment: ""),
                    isCompleted: isShareOnboarded,
                    isCritical: false,
                    actionLabel: isShareOnboarded ? "" : NSLocalizedString("ONBOARDING_SHARE_ACTION", bundle: .clawsy, comment: ""),
                    action: acknowledgeShare
                )

                // Step 5: Server Setup (optional)
                OnboardingStepRow(
                    icon: "server.rack",
                    title: NSLocalizedString("ONBOARDING_SERVER", bundle: .clawsy, comment: ""),
                    subtitle: NSLocalizedString("ONBOARDING_SERVER_DESC", bundle: .clawsy, comment: ""),
                    isCompleted: isServerSetupDone,
                    isCritical: false,
                    actionLabel: isServerSetupDone ? "" : NSLocalizedString("ONBOARDING_SERVER_COPY", bundle: .clawsy, comment: ""),
                    action: copyServerSetupPrompt
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            } // ScrollView

            Spacer(minLength: 0)

            Divider().opacity(0.3)

            // Footer
            HStack {
                Button(action: {
                    isPresented = false
                }) {
                    Text(l10n: "ONBOARDING_SKIP")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    onboardingCompleted = true
                    isPresented = false
                }) {
                    Text(l10n: "ONBOARDING_DONE")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!criticalStepsCompleted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 420, height: 480)
        .onAppear {
            refreshStatus()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                refreshStatus()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    // MARK: - Status Checks

    private func refreshStatus() {
        isInApplications = Bundle.main.bundlePath.hasPrefix("/Applications")
        let trusted = AXIsProcessTrusted()
        isAccessibilityGranted = trusted
        // If already trusted: clear restart hint and persist flag
        if trusted {
            accessibilityJustRequested = false
            accessibilityPreviouslyRequested = true
        }
        // Note: do NOT set accessibilityJustRequested = true here based on
        // accessibilityPreviouslyRequested. That @State flag is session-only
        // and only becomes true when the user clicks "Enable" in THIS session.
        // After a restart it resets to false → shows "Enable" button (correct).
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
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            isFinderSyncRunning = output.contains("+")
        } catch {
            isFinderSyncRunning = false
        }
    }

    // MARK: - Actions

    private func moveToApplications() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Bundle.main.bundlePath)])
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Mark as requested so future launches show "restart needed" immediately
        accessibilityPreviouslyRequested = true
        // After user dismisses the system dialog, show "restart" hint
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !AXIsProcessTrusted() {
                accessibilityJustRequested = true
            }
        }
    }

    private func restartApp() {
        // Use 'open -n' shell command — most reliable way to relaunch self
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    private func openFinderSyncSettings() {
        // macOS 13+ (Ventura/Sonoma/Sequoia): Login Items & Extensions
        // macOS 12 and below: old Extensions pane
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
            "x-apple.systempreferences:com.apple.preferences.extensions"
        ]
        for urlString in urls {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                showFinderSyncHint = true
                return
            }
        }
    }

    private func acknowledgeShare() {
        UserDefaults.standard.set(true, forKey: "clawsy_share_onboarded")
        isShareOnboarded = true
    }

    private func copyServerSetupPrompt() {
        let prompt = """
        Clawsy (macOS Companion App) is now installed and connected to this gateway. \
        Please install the server-side components so you can access clipboard history, \
        screenshots, and other cached events:

        1. Clone the repo: git clone https://github.com/iret77/clawsy.git /tmp/clawsy-setup
        2. Run setup: cd /tmp/clawsy-setup/server && chmod +x setup.sh && ./setup.sh
        3. Read the integration guide: cat /tmp/clawsy-setup/server/templates/CLAWSY.md

        After setup, add Clawsy heartbeat entries to your HEARTBEAT.md — \
        send agent.info and agent.status to clawsy-service every heartbeat. \
        See: https://github.com/iret77/clawsy/blob/main/server/templates/CLAWSY.md
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)

        isServerSetupDone = true
        UserDefaults.standard.set(true, forKey: "clawsy_server_setup_done")
    }

    private func enableFinderSync() {
        // First try pluginkit (works if extension is already registered)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-e", "use", "-i", "ai.clawsy.FinderSync"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        // Always show the hint so the user knows the manual path
        showFinderSyncHint = true

        // Recheck after short delay; if still not active, open Settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            checkFinderSyncStatus()
            if !isFinderSyncRunning {
                openFinderSyncSettings()
            }
        }
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
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    if !isCritical {
                        Text(l10n: "ONBOARDING_OPTIONAL")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !isCompleted && !actionLabel.isEmpty {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
