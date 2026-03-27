import Foundation

// MARK: - Gateway Agent

/// Represents a configured agent on the OpenClaw gateway.
public struct GatewayAgent: Identifiable, Equatable {
    public let id: String      // agent id (e.g. "main", "elliot")
    public let name: String    // display name (e.g. "CyberClaw", "Elliot")

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Gateway Channel

/// Represents a messaging channel connected to the OpenClaw gateway.
/// Used for the response channel picker — user chooses where agent replies go.
public struct GatewayChannel: Identifiable, Equatable {
    public let id: String          // channel type (e.g. "telegram", "slack", "discord")
    public let name: String        // display name (e.g. "Telegram", "Slack")
    public let isConnected: Bool

    public init(id: String, name: String, isConnected: Bool) {
        self.id = id
        self.name = name
        self.isConnected = isConnected
    }

    /// SF Symbol for the channel
    public var icon: String {
        switch id {
        case "telegram": return "paperplane.fill"
        case "slack": return "number"
        case "discord": return "gamecontroller.fill"
        case "whatsapp": return "message.fill"
        case "signal": return "lock.shield.fill"
        case "imessage": return "bubble.left.and.bubble.right.fill"
        case "webchat": return "globe"
        default: return "antenna.radiowaves.left.and.right"
        }
    }
}

/// Response channel preference — where the user wants agent replies
public enum ResponseChannel: Equatable {
    /// Reply appears as macOS notification + response panel in Clawsy
    case clawsy
    /// Reply goes to a specific external channel (Telegram, Slack, etc.)
    /// The sessionKey is the agent session bound to that channel.
    case external(channelId: String, sessionKey: String)
}

// MARK: - Gateway Session

/// Represents an active or recent session on the OpenClaw gateway.
public struct GatewaySession: Identifiable, Equatable {
    public let id: String        // session key
    public let label: String?
    public let kind: String
    public let status: String    // "running", "done", "error"
    public let model: String?
    public let startedAt: Date?
    public let task: String?

    public init(id: String, label: String?, kind: String, status: String,
                model: String?, startedAt: Date?, task: String?) {
        self.id = id
        self.label = label
        self.kind = kind
        self.status = status
        self.model = model
        self.startedAt = startedAt
        self.task = task
    }
}
