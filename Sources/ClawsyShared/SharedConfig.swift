import Foundation

public struct SharedConfig {
    public static let appGroup = "group.ai.openclaw.clawsy"
    
    public static var sharedDefaults: UserDefaults {
        let groupDefaults = UserDefaults(suiteName: appGroup) ?? .standard
        
        // --- BUILT-IN MIGRATION LOGIC (v0.4.5) ---
        // If the new group defaults are empty but old data exists, migrate it once.
        if !groupDefaults.bool(forKey: "migrationV1Done") {
            let standard = UserDefaults.standard
            if let oldHost = standard.string(forKey: "serverHost") { groupDefaults.set(oldHost, forKey: "serverHost") }
            if let oldPort = standard.string(forKey: "serverPort") { groupDefaults.set(oldPort, forKey: "serverPort") }
            if let oldToken = standard.string(forKey: "serverToken") { groupDefaults.set(oldToken, forKey: "serverToken") }
            groupDefaults.set(standard.bool(forKey: "extendedContextEnabled"), forKey: "extendedContextEnabled")
            if let oldUser = standard.string(forKey: "sshUser") { groupDefaults.set(oldUser, forKey: "sshUser") }
            groupDefaults.set(standard.bool(forKey: "useSshFallback"), forKey: "useSshFallback")
            if let oldPath = standard.string(forKey: "sharedFolderPath") { groupDefaults.set(oldPath, forKey: "sharedFolderPath") }
            if let oldBookmark = standard.data(forKey: "sharedFolderBookmark") { groupDefaults.set(oldBookmark, forKey: "sharedFolderBookmark") }
            if let oldQuick = standard.string(forKey: "quickSendHotkey") { groupDefaults.set(oldQuick, forKey: "quickSendHotkey") }
            if let oldPush = standard.string(forKey: "pushClipboardHotkey") { groupDefaults.set(oldPush, forKey: "pushClipboardHotkey") }
            
            // New v0.4.5 members initialization
            groupDefaults.set("{}", forKey: "activityProfile")
            groupDefaults.set("", forKey: "lastEnvelopeJSON")

            groupDefaults.set(true, forKey: "migrationV1Done")
            groupDefaults.synchronize()
        }
        return groupDefaults
    }
    
    public static var serverHost: String { sharedDefaults.string(forKey: "serverHost") ?? "" }
    public static var serverPort: String { sharedDefaults.string(forKey: "serverPort") ?? "18789" }
    public static var serverToken: String { sharedDefaults.string(forKey: "serverToken") ?? "" }
    public static var sshUser: String { sharedDefaults.string(forKey: "sshUser") ?? "" }
    public static var useSshFallback: Bool { sharedDefaults.bool(forKey: "useSshFallback") }
    
    public static var activityProfile: String {
        get { sharedDefaults.string(forKey: "activityProfile") ?? "{}" }
        set { sharedDefaults.set(newValue, forKey: "activityProfile") }
    }
    
    public static var lastEnvelopeJSON: String {
        get { sharedDefaults.string(forKey: "lastEnvelopeJSON") ?? "" }
        set { sharedDefaults.set(newValue, forKey: "lastEnvelopeJSON") }
    }

    public static var sharedFolderPath: String {
        get { sharedDefaults.string(forKey: "sharedFolderPath") ?? "" }
        set { sharedDefaults.set(newValue, forKey: "sharedFolderPath") }
    }
    
    public static var sharedFolderBookmark: Data? {
        get { sharedDefaults.data(forKey: "sharedFolderBookmark") }
        set { sharedDefaults.set(newValue, forKey: "sharedFolderBookmark") }
    }
    
    public static var extendedContextEnabled: Bool { sharedDefaults.bool(forKey: "extendedContextEnabled") }
    
    /// The session key that events are routed to (persisted for Share Extension access).
    public static var targetSessionKey: String {
        get { sharedDefaults.string(forKey: "targetSessionKey") ?? "clawsy-service" }
        set { sharedDefaults.set(newValue, forKey: "targetSessionKey"); sharedDefaults.synchronize() }
    }
    
    public static var quickSendHotkey: String { sharedDefaults.string(forKey: "quickSendHotkey") ?? "K" }
    public static var pushClipboardHotkey: String { sharedDefaults.string(forKey: "pushClipboardHotkey") ?? "V" }
    public static var cameraHotkey: String { sharedDefaults.string(forKey: "cameraHotkey") ?? "P" }
    public static var screenshotFullHotkey: String { sharedDefaults.string(forKey: "screenshotFullHotkey") ?? "S" }
    public static var screenshotAreaHotkey: String { sharedDefaults.string(forKey: "screenshotAreaHotkey") ?? "A" }
    
    public static var shortVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.6.0" }
    public static var buildNumber: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    public static var versionDisplay: String { "v\(shortVersion) #\(buildNumber)" }
    
    public static func save(host: String, port: String, token: String) {
        let defaults = sharedDefaults
        defaults.set(host, forKey: "serverHost")
        defaults.set(port, forKey: "serverPort")
        defaults.set(token, forKey: "serverToken")
        defaults.synchronize()
    }
    
    public static var resolvedFolderUrl: URL? = nil

    @discardableResult
    public static func resolveBookmark() -> URL? {
        if let existing = resolvedFolderUrl { return existing }
        guard let data = sharedFolderBookmark else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                let newData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                sharedFolderBookmark = newData
            }
            if url.startAccessingSecurityScopedResource() { 
                resolvedFolderUrl = url
                return url 
            }
            return nil
        } catch {
            return nil
        }
    }
}
