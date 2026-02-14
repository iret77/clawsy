import Foundation

public struct SharedConfig {
    public static let appGroup = "group.ai.clawsy"
    
    public static var sharedDefaults: UserDefaults {
        return UserDefaults(suiteName: appGroup) ?? .standard
    }
    
    public static var serverHost: String { sharedDefaults.string(forKey: "serverHost") ?? "" }
    public static var serverPort: String { sharedDefaults.string(forKey: "serverPort") ?? "18789" }
    public static var serverToken: String { sharedDefaults.string(forKey: "serverToken") ?? "" }
    
    public static func save(host: String, port: String, token: String) {
        let defaults = sharedDefaults
        defaults.set(host, forKey: "serverHost")
        defaults.set(port, forKey: "serverPort")
        defaults.set(token, forKey: "serverToken")
        defaults.synchronize()
    }
}
