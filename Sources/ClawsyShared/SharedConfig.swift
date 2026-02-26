import Foundation

public struct SharedConfig {
    public static let appGroup = "group.ai.openclaw.clawsy"
    
    public static var sharedDefaults: UserDefaults {
        let groupDefaults = UserDefaults(suiteName: appGroup) ?? .standard
        
        // Migration Check: If group defaults are empty, try to migrate from standard
        if groupDefaults.string(forKey: "serverHost") == nil {
            let standard = UserDefaults.standard
            if let oldHost = standard.string(forKey: "serverHost") {
                groupDefaults.set(oldHost, forKey: "serverHost")
                groupDefaults.set(standard.string(forKey: "serverPort"), forKey: "serverPort")
                groupDefaults.set(standard.string(forKey: "serverToken"), forKey: "serverToken")
                groupDefaults.set(standard.bool(forKey: "extendedContextEnabled"), forKey: "extendedContextEnabled")
                groupDefaults.set(standard.string(forKey: "sshUser"), forKey: "sshUser")
                groupDefaults.set(standard.bool(forKey: "useSshFallback"), forKey: "useSshFallback")
                groupDefaults.set(standard.string(forKey: "sharedFolderPath"), forKey: "sharedFolderPath")
                groupDefaults.synchronize()
            }
        }
        
        return groupDefaults
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
