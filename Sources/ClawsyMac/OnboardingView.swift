import SwiftUI
import ClawsyShared

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Binding var onboardingCompleted: Bool
    
    @State private var isInApplications = false
    @State private var isAccessibilityGranted = false
    @State private var isFinderSyncRunning = false
    @State private var refreshTimer: Timer?
    
    private var criticalStepsCompleted: Bool {
        isInApplications && isAccessibilityGranted
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image("OnboardingLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                
                Text("ONBOARDING_TITLE", bundle: .clawsy)
                    .font(.system(size: 18, weight: .bold))
                
                Text("ONBOARDING_SUBTITLE", bundle: .clawsy)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider().opacity(0.3)
            
            // Checklist
            VStack(spacing: 16) {
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
                OnboardingStepRow(
                    icon: "hand.raised.fill",
                    title: NSLocalizedString("ONBOARDING_ACCESSIBILITY", bundle: .clawsy, comment: ""),
                    subtitle: NSLocalizedString("ONBOARDING_ACCESSIBILITY_DESC", bundle: .clawsy, comment: ""),
                    isCompleted: isAccessibilityGranted,
                    isCritical: true,
                    actionLabel: NSLocalizedString("ONBOARDING_OPEN_SETTINGS", bundle: .clawsy, comment: ""),
                    action: openAccessibilitySettings
                )
                
                // Step 3: FinderSync (optional)
                OnboardingStepRow(
                    icon: "folder.badge.gearshape",
                    title: NSLocalizedString("ONBOARDING_FINDERSYNC", bundle: .clawsy, comment: ""),
                    subtitle: NSLocalizedString("ONBOARDING_FINDERSYNC_DESC", bundle: .clawsy, comment: ""),
                    isCompleted: isFinderSyncRunning,
                    isCritical: false,
                    actionLabel: NSLocalizedString("ONBOARDING_ENABLE", bundle: .clawsy, comment: ""),
                    action: openFinderSyncSettings
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            
            Spacer()
            
            Divider().opacity(0.3)
            
            // Footer
            HStack {
                Button(action: {
                    isPresented = false
                }) {
                    Text("ONBOARDING_SKIP", bundle: .clawsy)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
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
        .frame(width: 420, height: 440)
        .onAppear {
            refreshStatus()
            // Poll status every 2 seconds while visible
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
        isAccessibilityGranted = AXIsProcessTrusted()
        // FIFinderSyncController not available in main app — check via pluginkit
        checkFinderSyncStatus()
    }
    
    private func checkFinderSyncStatus() {
        // Best-effort check: see if the extension process is running
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
            // If pluginkit lists it with a "+", it's enabled
            isFinderSyncRunning = output.contains("+")
        } catch {
            isFinderSyncRunning = false
        }
    }
    
    // MARK: - Actions
    
    private func moveToApplications() {
        // Reveal /Applications in Finder
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Applications")
        // Also reveal current app location
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Bundle.main.bundlePath)])
    }
    
    private func openAccessibilitySettings() {
        // Request accessibility (shows system prompt if not trusted)
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    private func openFinderSyncSettings() {
        // Open Extensions preference pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
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
            // Status indicator
            Image(systemName: isCompleted ? "checkmark.circle.fill" : (isCritical ? "exclamationmark.triangle.fill" : "circle.dashed"))
                .font(.system(size: 20))
                .foregroundColor(isCompleted ? .green : (isCritical ? .orange : .secondary))
                .frame(width: 24)
            
            // Text
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
            
            // Action button (only if not completed)
            if !isCompleted {
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
