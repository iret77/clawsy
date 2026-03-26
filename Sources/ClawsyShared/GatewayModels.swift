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
