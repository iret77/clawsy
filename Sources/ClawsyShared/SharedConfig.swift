import Foundation

public struct SharedConfig {
    public static let appGroup = "group.ai.openclaw.clawsy"
    
    public static var sharedDefaults: UserDefaults {
        let groupDefaults = UserDefaults(suiteName: appGroup) ?? .standard
        
        // --- BUILT-IN MIGRATION LOGIC (v0.4.5) ---
        // If the new group defaults are empty but old data exists, migrate it once.
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
                if let oldBookmark = standard.data(forKey: "sharedFolderBookmark") {
                    groupDefaults.set(oldBookmark, forKey: "sharedFolderBookmark")
                }
                groupDefaults.synchronize()
            }
        }
        return groupDefaults
    }
    
    public static var serverHost: String { sharedDefaults.string(forKey: "serverHost") ?? "" }
    public static var serverPort: String { sharedDefaults.string(forKey: "serverPort") ?? "18789" }
    public static var serverToken: String { sharedDefaults.string(forKey: "serverToken") ?? "" }
    public static var sshUser: String { sharedDefaults.string(forKey: "sshUser") ?? "" }
    public static var useSshFallback: Bool { sharedDefaults.bool(forKey: "useSshFallback") }
    
    public static var sharedFolderPath: String {
        get { sharedDefaults.string(forKey: "sharedFolderPath") ?? "" }
        set { sharedDefaults.set(newValue, forKey: "sharedFolderPath") }
    }
    
    public static var sharedFolderBookmark: Data? {
        get { sharedDefaults.data(forKey: "sharedFolderBookmark") }
        set { sharedDefaults.set(newValue, forKey: "sharedFolderBookmark") }
    }
    
    public static var extendedContextEnabled: Bool { sharedDefaults.bool(forKey: "extendedContextEnabled") }
    
    public static var quickSendHotkey: String { sharedDefaults.string(forKey: "quickSendHotkey") ?? "K" }
    public static var pushClipboardHotkey: String { sharedDefaults.string(forKey: "pushClipboardHotkey") ?? "V" }
    
    public static var shortVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.5" }
    public static var buildNumber: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    public static var versionDisplay: String { "v\(shortVersion) #\(buildNumber)" }
    
    public static func save(host: String, port: String, token: String) {
        let defaults = sharedDefaults
        defaults.set(host, forKey: "serverHost")
        defaults.set(port, forKey: "serverPort")
        defaults.set(token, forKey: "serverToken")
        defaults.synchronize()
    }
    
    public static func resolveBookmark() -> URL? {
        guard let data = sharedFolderBookmark else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                let newData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                sharedFolderBookmark = newData
            }
            if url.startAccessingSecurityScopedResource() { return url }
            return nil
        } catch {
            return nil
        }
    }
}
