import Foundation

/// Shared communication layer between FinderSync extension and main app.
/// Uses App Group container + DistributedNotificationCenter (cross-process).
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
    private static let notificationName = Notification.Name("ai.clawsy.pendingAction")

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
        DistributedNotificationCenter.default().postNotificationName(
            notificationName, object: nil, userInfo: nil, deliverImmediately: true
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

    /// Observer token — stored to prevent duplicates and allow cleanup.
    private static var observerToken: NSObjectProtocol?

    /// Main app registers for cross-process notifications from FinderSync.
    /// Safe to call multiple times — replaces any previous observer.
    public static func observe(callback: @escaping () -> Void) {
        if let token = observerToken {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        observerToken = DistributedNotificationCenter.default().addObserver(
            forName: notificationName, object: nil, queue: .main
        ) { _ in
            callback()
        }
    }
}
