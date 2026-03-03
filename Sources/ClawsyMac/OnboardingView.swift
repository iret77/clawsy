import SwiftUI
import ClawsyShared

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Binding var onboardingCompleted: Bool

    @State private var isInApplications = false
    @State private var isAccessibilityGranted = false
    @State private var isFinderSyncRunning = false
    @State private var isShareOnboarded = false
    @State private var refreshTimer: Timer?
    @State private var accessibilityJustRequested = false
    @State private var accessibilityUserConfirmed = false

    private var criticalStepsCompleted: Bool {
        isInApplications && (isAccessibilityGranted || accessibilityUserConfirmed)
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
                    Text("ONBOARDING_TITLE", bundle: .clawsy)
                        .font(.system(size: 16, weight: .bold))
                    Text("ONBOARDING_SUBTITLE", bundle: .clawsy)
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
                                Text("ONBOARDING_ACCESSIBILITY_SKIP_RESTART", bundle: .clawsy)
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
                    if !isFinderSyncRunning {
                        HStack {
                            Spacer()
                            Button(action: openFinderSyncSettings) {
                                Label(NSLocalizedString("ONBOARDING_FINDERSYNC_OPEN_SETTINGS", bundle: .clawsy, comment: ""), systemImage: "gear")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
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
                    Text("ONBOARDING_SKIP", bundle: .clawsy)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    onboardingCompleted = true
                    isPresented = false
                }) {
                    Text("ONBOARDING_DONE", bundle: .clawsy)
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
        // If user just granted, no longer need the "restart" hint
        if trusted { accessibilityJustRequested = false }
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
        let urls = [
            "x-apple.systempreferences:com.apple.preferences.extensions.FinderSync",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?Finder"
        ]
        for urlString in urls {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    private func acknowledgeShare() {
        UserDefaults.standard.set(true, forKey: "clawsy_share_onboarded")
        isShareOnboarded = true
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

        // Recheck after short delay; if still not active, open Finder Extensions pane
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            checkFinderSyncStatus()
            if !isFinderSyncRunning {
                // Open specifically the Finder Extensions panel (not generic Extensions)
                let urls = [
                    "x-apple.systempreferences:com.apple.preferences.extensions.FinderSync",
                    "x-apple.systempreferences:com.apple.ExtensionsPreferences?Finder"
                ]
                for urlString in urls {
                    if let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                        break
                    }
                }
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
                        Text("ONBOARDING_OPTIONAL", bundle: .clawsy)
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
