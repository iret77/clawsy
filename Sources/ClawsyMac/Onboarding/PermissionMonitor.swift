import Foundation
import AVFoundation
import UserNotifications
import os.log
import ClawsyShared

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
        case .screenRecording: return "display"
        case .camera: return "camera"
        case .accessibility: return "hand.raised"
        case .notifications: return "bell"
        }
    }

    public var description: String {
        switch self {
        case .screenRecording: return NSLocalizedString("PERM_BANNER_SCREEN_RECORDING_DESC", bundle: .clawsy, comment: "")
        case .camera: return NSLocalizedString("PERM_BANNER_CAMERA_DESC", bundle: .clawsy, comment: "")
        case .accessibility: return NSLocalizedString("PERM_BANNER_ACCESSIBILITY_DESC", bundle: .clawsy, comment: "")
        case .notifications: return NSLocalizedString("PERM_BANNER_NOTIFICATIONS_DESC", bundle: .clawsy, comment: "")
        }
    }

    /// User-facing display name — not the macOS technical label.
    public var displayName: String {
        return NSLocalizedString("PERM_BANNER_\(settingsKey)_TITLE", bundle: .clawsy, comment: "")
    }

    /// Stable key for building localization string IDs (e.g. "PERM_BANNER_SCREEN_RECORDING_TITLE").
    public var settingsKey: String {
        switch self {
        case .screenRecording: return "SCREEN_RECORDING"
        case .camera: return "CAMERA"
        case .accessibility: return "ACCESSIBILITY"
        case .notifications: return "NOTIFICATIONS"
        }
    }

    /// Whether this permission is essential (blocks core functionality) or optional.
    public var isRequired: Bool {
        switch self {
        case .screenRecording, .accessibility: return true
        case .camera, .notifications: return false
        }
    }

    /// Whether macOS offers a native one-click grant dialog for this permission.
    /// Camera and Notifications show Allow/Deny dialogs.
    /// Accessibility and Screen Recording only offer "Open System Settings" — no direct grant.
    public var hasNativeGrant: Bool {
        switch self {
        case .camera, .notifications: return true
        case .screenRecording, .accessibility: return false
        }
    }
}

// MARK: - Permission Monitor

/// Reference-counted permission monitor. Polls macOS TCC status at 1 Hz only
/// while at least one consumer is registered — saves energy when nobody is watching.
///
/// After a permission request, performs triple delayed re-checks at 0.3s, 0.9s, and
/// 1.8s to catch TCC propagation delays — eliminates the need for app restart that
/// macOS developers commonly encounter with ad-hoc signed builds.
///
/// Pattern adapted from the official OpenClaw Mac app's PermissionManager.
@MainActor
public final class PermissionMonitor: ObservableObject {

    // MARK: - Shared Instance

    static let shared = PermissionMonitor()

    // MARK: - Published State

    @Published public var status: [ClawsyPermission: Bool] = [:]

    // MARK: - Reference-counted Polling

    private var consumerCount = 0
    private var timer: Timer?
    private let logger = OSLog(subsystem: "ai.clawsy", category: "Permissions")

    /// Delays for re-check after requesting a permission (catches TCC propagation).
    private static let reCheckDelays: [TimeInterval] = [0.3, 0.9, 1.8]

    private init() {
        refreshAll()
    }

    /// Register a consumer that needs live status updates. Timer starts on first
    /// consumer and stops when the last one unregisters.
    public func register() {
        consumerCount += 1
        if consumerCount == 1 { startPolling() }
    }

    /// Unregister a consumer. Timer stops when no consumers remain.
    public func unregister() {
        if consumerCount <= 0 {
            os_log("PermissionMonitor: unregister() called with no registered consumers", log: logger, type: .error)
            return
        }
        consumerCount -= 1
        if consumerCount == 0 { stopPolling() }
    }

    private func startPolling() {
        stopPolling()
        refreshAll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
    }

    private func stopPolling() {
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

    /// Missing required permissions.
    public var missingRequired: [ClawsyPermission] {
        ClawsyPermission.allCases.filter { $0.isRequired && status[$0] != true }
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
        // Try modern API first (matches official OpenClaw app).
        if CGPreflightScreenCaptureAccess() { return true }
        // Fallback: CGPreflightScreenCaptureAccess can return false for ad-hoc signed
        // builds even after permission is granted. The CGWindowList approach is more
        // reliable in practice — if we can see other apps' windows, permission is granted.
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let myPID = ProcessInfo.processInfo.processIdentifier
        return windowList.contains { ($0[kCGWindowOwnerPID as String] as? Int32) != myPID }
    }

    // MARK: - Request + Triple Delayed Re-check

    /// Request a permission and schedule triple delayed re-checks to detect
    /// TCC propagation without requiring an app restart.
    public func requestAndMonitor(_ perm: ClawsyPermission) {
        requestPermission(perm)
    }

    /// Trigger the system permission prompt or open Settings if already denied.
    /// Automatically schedules triple delayed re-checks for TCC propagation.
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

        scheduleDelayedReChecks()
    }

    /// Schedule re-checks at 0.3s, 0.9s, and 1.8s to catch TCC propagation delays.
    private func scheduleDelayedReChecks() {
        for delay in Self.reCheckDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshAll()
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

        // Re-check after user may have toggled permission in Settings
        scheduleDelayedReChecks()
    }
}
