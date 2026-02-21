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
    
    // Persisted envelope for transparency view
    public static var lastEnvelopeJSON: String {
        get { sharedDefaults.string(forKey: "lastEnvelopeJSON") ?? "" }
        set { sharedDefaults.set(newValue, forKey: "lastEnvelopeJSON") }
    }
    
    // Hotkeys
    public static var quickSendHotkey: String { sharedDefaults.string(forKey: "quickSendHotkey") ?? "K" }
    public static var pushClipboardHotkey: String { sharedDefaults.string(forKey: "pushClipboardHotkey") ?? "V" }
    
    // Version helpers
    public static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    
    public static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    
    public static var versionDisplay: String {
        "v\(shortVersion) #\(buildNumber)"
    }
    
    public static var logVersionDisplay: String {
        "Clawsy v\(shortVersion)"
    }
    
    public static func save(host: String, port: String, token: String) {
        let defaults = sharedDefaults
        defaults.set(host, forKey: "serverHost")
        defaults.set(port, forKey: "serverPort")
        defaults.set(token, forKey: "serverToken")
        defaults.synchronize()
    }
}
