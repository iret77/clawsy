import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Represents a single OpenClaw gateway host configuration.
/// Each host has its own connection settings, color, and isolated shared folder.
public struct HostProfile: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var gatewayHost: String
    public var gatewayPort: String   // default "18789"
    public var serverToken: String
    public var sshUser: String
    public var useSshFallback: Bool
    public var sshOnly: Bool         // skip WSS, always use SSH tunnel
    public var color: String         // hex e.g. "#FF3B30"
    public var sharedFolderPath: String  // e.g. "~/Clawsy/CyberClaw/"
    public var deviceToken: String?

    public init(
        id: UUID = UUID(),
        name: String,
        gatewayHost: String,
        gatewayPort: String = "18789",
        serverToken: String,
        sshUser: String = "",
        useSshFallback: Bool = true,
        sshOnly: Bool = false,
        color: String = "#FF3B30",
        sharedFolderPath: String = "",
        deviceToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.gatewayHost = gatewayHost
        self.gatewayPort = gatewayPort
        self.serverToken = serverToken
        self.sshUser = sshUser
        self.useSshFallback = useSshFallback
        self.sshOnly = sshOnly
        self.color = color
        self.sharedFolderPath = sharedFolderPath
        self.deviceToken = deviceToken
    }

    // Custom decoder for backward compatibility — old profiles lack sshOnly
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        gatewayHost = try container.decode(String.self, forKey: .gatewayHost)
        gatewayPort = try container.decode(String.self, forKey: .gatewayPort)
        serverToken = try container.decode(String.self, forKey: .serverToken)
        sshUser = try container.decode(String.self, forKey: .sshUser)
        useSshFallback = try container.decode(Bool.self, forKey: .useSshFallback)
        sshOnly = try container.decodeIfPresent(Bool.self, forKey: .sshOnly) ?? false
        color = try container.decode(String.self, forKey: .color)
        sharedFolderPath = try container.decode(String.self, forKey: .sharedFolderPath)
        deviceToken = try container.decodeIfPresent(String.self, forKey: .deviceToken)
    }

    /// Default host colors for new profiles (cycle through these)
    public static let defaultColors = [
        "#FF3B30", // Red
        "#007AFF", // Blue
        "#34C759", // Green
        "#FF9500", // Orange
        "#AF52DE", // Purple
        "#FF2D55", // Pink
        "#5AC8FA", // Cyan
        "#FFCC00"  // Yellow
    ]
}

// MARK: - Color Extensions

#if canImport(SwiftUI)
extension Color {
    /// Initialize a Color from a hex string like "#FF3B30" or "FF3B30"
    public init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let hexNumber = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        let r = Double((hexNumber & 0xFF0000) >> 16) / 255
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255
        let b = Double(hexNumber & 0x0000FF) / 255

        self.init(red: r, green: g, blue: b)
    }
}
#endif

#if canImport(AppKit)
extension NSColor {
    /// Initialize an NSColor from a hex string like "#FF3B30"
    public convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let hexNumber = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        let r = CGFloat((hexNumber & 0xFF0000) >> 16) / 255
        let g = CGFloat((hexNumber & 0x00FF00) >> 8) / 255
        let b = CGFloat(hexNumber & 0x0000FF) / 255

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
#endif
