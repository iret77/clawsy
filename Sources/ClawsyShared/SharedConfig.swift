import Foundation

public struct SharedConfig {
    public static let appGroup = "group.ai.clawsy"
    
    public static var sharedDefaults: UserDefaults {
        return UserDefaults(suiteName: appGroup) ?? .standard
    }
    
    public static var serverHost: String { sharedDefaults.string(forKey: "serverHost") ?? "" }
    public static var serverPort: String { sharedDefaults.string(forKey: "serverPort") ?? "18789" }
    public static var serverToken: String { sharedDefaults.string(forKey: "serverToken") ?? "" }
    
    public static var extendedContextEnabled: Bool { sharedDefaults.bool(forKey: "extendedContextEnabled") }
    
    // Activity Profile (Compressed JSON string of daily activity ranges)
    public static var activityProfile: String {
        get { sharedDefaults.string(forKey: "activityProfile") ?? "{}" }
        set { sharedDefaults.set(newValue, forKey: "activityProfile") }
    }
    
    // Hotkeys
    public static var quickSendHotkey: String { sharedDefaults.string(forKey: "quickSendHotkey") ?? "K" }
    public static var pushClipboardHotkey: String { sharedDefaults.string(forKey: "pushClipboardHotkey") ?? "V" }
    
    public static func save(host: String, port: String, token: String) {
        let defaults = sharedDefaults
        defaults.set(host, forKey: "serverHost")
        defaults.set(port, forKey: "serverPort")
        defaults.set(token, forKey: "serverToken")
        defaults.synchronize()
    }
}
