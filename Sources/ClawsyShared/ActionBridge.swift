import Foundation

/// Shared communication layer between FinderSync extension and main app.
/// Uses App Group container + Darwin notifications.
public struct PendingAction: Codable {
    public let id: String
    public let kind: String       // "open_rule_editor" | "send_telemetry" | "run_actions"
    public let folderPath: String
    public let timestamp: Date

    public init(kind: String, folderPath: String) {
        self.id = UUID().uuidString
        self.kind = kind
        self.folderPath = folderPath
        self.timestamp = Date()
    }
}

public class ActionBridge {
    public static let darwinNotificationName = "ai.clawsy.pendingAction" as CFString

    private static var pendingActionURL: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.ai.openclaw.clawsy"
        ) else { return nil }
        return container.appendingPathComponent("pending_action.json")
    }

    /// Called by FinderSync extension to post an action
    public static func postAction(_ action: PendingAction) {
        guard let url = pendingActionURL else { return }
        if let data = try? JSONEncoder().encode(action) {
            try? data.write(to: url, options: .atomic)
        }
        // Wake the main app via Darwin notification
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinNotificationName),
            nil, nil, true
        )
    }

    /// Called by main app to consume the pending action (returns and clears it)
    public static func consumeAction() -> PendingAction? {
        guard let url = pendingActionURL,
              let data = try? Data(contentsOf: url),
              let action = try? JSONDecoder().decode(PendingAction.self, from: data)
        else { return nil }
        try? FileManager.default.removeItem(at: url)
        return action
    }

    /// Main app registers for Darwin notifications
    public static func observe(callback: @escaping () -> Void) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passRetained(callback as AnyObject).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, _, _, _, _ in
            DispatchQueue.main.async { callback() }
        }, darwinNotificationName, nil, .deliverImmediately)
    }
}
