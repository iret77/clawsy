import Foundation
import AVFoundation
import UserNotifications
import os.log

#if canImport(AppKit)
import AppKit
import ApplicationServices
#endif

// MARK: - Permission Capability

/// The macOS permissions Clawsy needs. Smaller set than the official app
/// because Clawsy doesn't do exec approvals, speech, or location.
public enum ClawsyPermission: String, CaseIterable, Identifiable {
    case screenRecording = "Screen Recording"
    case camera = "Camera"
    case accessibility = "Accessibility"
    case notifications = "Notifications"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .screenRecording: return "rectangle.dashed.and.arrow.up"
        case .camera: return "camera.fill"
        case .accessibility: return "accessibility"
        case .notifications: return "bell.badge.fill"
        }
    }

    public var description: String {
        switch self {
        case .screenRecording: return "Required for capturing screenshots to share with your agent."
        case .camera: return "Required for taking photos with your Mac or iPhone camera."
        case .accessibility: return "Required for global keyboard shortcuts (⌘⇧K, etc.)."
        case .notifications: return "Allows Clawsy to notify you about agent activity."
        }
    }

    /// Whether this permission is essential (blocks core functionality) or optional.
    public var isRequired: Bool {
        switch self {
        case .screenRecording, .accessibility: return true
        case .camera, .notifications: return false
        }
    }
}

// MARK: - Permission Monitor

/// Polls macOS permission status every second (like the official OpenClaw app).
/// Publishes a dictionary of capability → granted status.
@MainActor
public final class PermissionMonitor: ObservableObject {

    @Published public var status: [ClawsyPermission: Bool] = [:]

    private var timer: Timer?
    private let logger = OSLog(subsystem: "ai.clawsy", category: "Permissions")

    public init() {
        refreshAll()
    }

    /// Start live polling (call when permissions page is visible).
    public func startPolling() {
        stopPolling()
        refreshAll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
    }

    /// Stop live polling (call when leaving permissions page).
    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Check all permissions once.
    public func refreshAll() {
        for perm in ClawsyPermission.allCases {
            status[perm] = checkPermission(perm)
        }
    }

    /// All required permissions granted?
    public var allRequiredGranted: Bool {
        ClawsyPermission.allCases.filter(\.isRequired).allSatisfy { status[$0] == true }
    }

    /// All permissions granted (including optional)?
    public var allGranted: Bool {
        ClawsyPermission.allCases.allSatisfy { status[$0] == true }
    }

    // MARK: - Check

    private func checkPermission(_ perm: ClawsyPermission) -> Bool {
        switch perm {
        case .screenRecording:
            return checkScreenRecording()
        case .camera:
            return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        case .accessibility:
            return AXIsProcessTrusted()
        case .notifications:
            // Synchronous check via semaphore (OK on main thread for quick poll)
            var granted = false
            let sem = DispatchSemaphore(value: 0)
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                granted = settings.authorizationStatus == .authorized
                sem.signal()
            }
            sem.wait()
            return granted
        }
    }

    private func checkScreenRecording() -> Bool {
        // CGWindowListCopyWindowInfo succeeds only if Screen Recording is granted.
        // On denial it returns an empty array for windows of other apps.
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        // If we can see windows from other apps (not just our own), permission is granted
        let myPID = ProcessInfo.processInfo.processIdentifier
        return windowList.contains { ($0[kCGWindowOwnerPID as String] as? Int32) != myPID }
    }

    // MARK: - Request / Open Settings

    /// Trigger the system permission prompt or open Settings if already denied.
    public func requestPermission(_ perm: ClawsyPermission) {
        switch perm {
        case .screenRecording:
            CGRequestScreenCaptureAccess()

        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                Task { @MainActor in self.refreshAll() }
            }

        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)

        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                Task { @MainActor in self.refreshAll() }
            }
        }
    }

    /// Open the relevant System Settings pane (when permission was denied and can't be re-prompted).
    public func openSettings(for perm: ClawsyPermission) {
        let urlString: String
        switch perm {
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .camera:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .notifications:
            urlString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
