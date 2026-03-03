import Foundation

/// Classifies connection failures into actionable error types with user-facing
/// German descriptions and ready-to-paste fix prompts for OpenClaw chat.
public enum ConnectionError: Equatable {
    case originNotAllowed
    case invalidToken
    case sshTunnelFailed
    case hostUnreachable
    case gatewayNotRunning
    case unknownDisconnect(reason: String)

    // MARK: - User-Facing Strings (German)

    public var title: String {
        switch self {
        case .originNotAllowed:     return "Origin nicht erlaubt"
        case .invalidToken:         return "Authentifizierungsfehler"
        case .sshTunnelFailed:      return "SSH-Tunnel fehlgeschlagen"
        case .hostUnreachable:      return "Gateway nicht erreichbar"
        case .gatewayNotRunning:    return "Gateway antwortet nicht"
        case .unknownDisconnect:    return "Verbindungsfehler"
        }
    }

    public var description: String {
        switch self {
        case .originNotAllowed:
            return "Das Gateway lehnt die Verbindung ab, weil der Clawsy-Origin nicht in der Allowlist steht."
        case .invalidToken:
            return "Der konfigurierte Token stimmt nicht mit dem Gateway-Token überein."
        case .sshTunnelFailed:
            return "Der SSH-Tunnel konnte nicht aufgebaut werden. Prüfe SSH-User und Host in den Einstellungen."
        case .hostUnreachable:
            return "Das Gateway ist nicht erreichbar. Prüfe ob OpenClaw läuft und Host/Port korrekt sind."
        case .gatewayNotRunning:
            return "Der SSH-Tunnel steht, aber das Gateway antwortet nicht auf localhost."
        case .unknownDisconnect(let reason):
            return "Verbindung getrennt: \(reason)"
        }
    }

    /// A ready-to-paste message the user can send to their OpenClaw agent to get help fixing the issue.
    /// Returns `nil` when the fix is purely user-side (e.g. check settings).
    public var fixPrompt: String? {
        switch self {
        case .originNotAllowed:
            return """
            Mein Clawsy kann sich nicht verbinden. Fehlermeldung: "origin not allowed". \
            Bitte füge `gateway.controlUi.allowedOrigins: ["*"]` zur Gateway-Config hinzu und starte das Gateway neu.
            """
        case .invalidToken:
            return """
            Mein Clawsy meldet einen Authentifizierungsfehler (INVALID_TOKEN). \
            Bitte prüfe ob der Token in den Clawsy-Einstellungen mit dem Gateway-Token übereinstimmt.
            """
        case .sshTunnelFailed:
            return """
            Mein Clawsy kann keinen SSH-Tunnel aufbauen. Bitte prüfe ob SSH-User und Host in den Einstellungen korrekt sind \
            und ob der Gateway-Host per SSH erreichbar ist.
            """
        case .hostUnreachable:
            return """
            Mein Clawsy kann das Gateway nicht erreichen (Verbindungs-Timeout). \
            Bitte prüfe ob OpenClaw läuft und der Gateway-Host/Port korrekt eingestellt ist.
            """
        case .gatewayNotRunning:
            return """
            Mein Clawsy hat einen SSH-Tunnel aufgebaut, aber das Gateway antwortet nicht auf localhost. \
            Bitte prüfe ob das OpenClaw Gateway auf dem Server läuft (`openclaw gateway status`).
            """
        case .unknownDisconnect:
            return nil
        }
    }

    public var fixAction: FixAction {
        switch self {
        case .originNotAllowed, .hostUnreachable, .gatewayNotRunning:
            if let prompt = fixPrompt {
                return .copyPromptToClipboard(prompt)
            }
            return .none
        case .invalidToken:
            return .openSettings  // User can also copy the prompt, but settings is primary
        case .sshTunnelFailed:
            return .openSettings
        case .unknownDisconnect:
            return .none
        }
    }

    // MARK: - Fix Action

    public enum FixAction: Equatable {
        case copyPromptToClipboard(String)
        case openSettings
        case none
    }

    // MARK: - Detection Helpers

    /// Attempt to classify a WebSocket disconnect reason string.
    public static func classify(disconnectReason: String, code: UInt16) -> ConnectionError? {
        let lower = disconnectReason.lowercased()

        // Origin not allowed (code 1008 is policy violation, but also check message)
        if lower.contains("origin not allowed") || lower.contains("origin_not_allowed") || code == 1008 && lower.contains("origin") {
            return .originNotAllowed
        }

        // Invalid token
        if lower.contains("invalid_token") || lower.contains("invalid token") || lower.contains("auth_token_mismatch") {
            return .invalidToken
        }

        // If we have a non-empty reason that doesn't match known patterns
        if !disconnectReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unknownDisconnect(reason: disconnectReason)
        }

        return nil
    }

    /// Classify based on connection failure context.
    public static func classify(connectionStatus: String, usingSshTunnel: Bool, sshConfigured: Bool) -> ConnectionError? {
        switch connectionStatus {
        case "STATUS_SSH_FAILED":
            return .sshTunnelFailed
        case "STATUS_SSH_USER_MISSING":
            return .sshTunnelFailed
        case "STATUS_OFFLINE_REFUSED":
            return usingSshTunnel ? .gatewayNotRunning : .hostUnreachable
        case "STATUS_OFFLINE_TIMEOUT":
            return .hostUnreachable
        case "STATUS_HANDSHAKE_FAILED":
            return .invalidToken
        default:
            return nil
        }
    }
}
