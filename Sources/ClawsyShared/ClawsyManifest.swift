import Foundation

/// A rule in a .clawsy manifest file
public struct ClawsyRule: Codable, Identifiable {
    public var id: String
    public var trigger: String    // "file_added" | "file_changed" | "manual"
    public var filter: String     // glob pattern e.g. "*.pdf", "*" for all
    public var action: String     // "send_to_agent" | "notify" | "move"
    public var prompt: String     // For "send_to_agent": the prompt prefix

    public init(id: String = UUID().uuidString,
                trigger: String = "file_added",
                filter: String = "*",
                action: String = "send_to_agent",
                prompt: String = "") {
        self.id = id
        self.trigger = trigger
        self.filter = filter
        self.action = action
        self.prompt = prompt
    }
}

/// The .clawsy manifest for a folder
public struct ClawsyManifest: Codable {
    public var version: Int = 1
    public var folderName: String
    public var rules: [ClawsyRule]
    public var createdAt: Date
    public var updatedAt: Date

    public init(folderName: String, rules: [ClawsyRule] = []) {
        self.folderName = folderName
        self.rules = rules
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Manages .clawsy files in folders
public class ClawsyManifestManager {
    public static let manifestFileName = ".clawsy"

    /// Returns the .clawsy file URL for a given folder
    public static func manifestURL(for folderPath: String) -> URL {
        URL(fileURLWithPath: folderPath).appendingPathComponent(manifestFileName)
    }

    /// Reads the manifest for a folder, or nil if it doesn't exist
    public static func read(for folderPath: String) -> ClawsyManifest? {
        let url = manifestURL(for: folderPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ClawsyManifest.self, from: data)
    }

    /// Writes (or creates) the manifest for a folder
    public static func write(_ manifest: ClawsyManifest, to folderPath: String) {
        let url = manifestURL(for: folderPath)
        var m = manifest
        m.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(m) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Ensures a .clawsy file exists for the given folder (creates empty one if not)
    @discardableResult
    public static func provision(for folderPath: String) -> ClawsyManifest {
        if let existing = read(for: folderPath) { return existing }
        let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        let manifest = ClawsyManifest(folderName: folderName)
        write(manifest, to: folderPath)
        return manifest
    }

    /// Provisions .clawsy for root shared folder and all immediate subfolders
    public static func provisionAll(in sharedFolderPath: String) {
        let root = (sharedFolderPath as NSString).expandingTildeInPath
        provision(for: root)

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: root) else { return }
        for item in contents {
            var isDir: ObjCBool = false
            let fullPath = (root as NSString).appendingPathComponent(item)
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                provision(for: fullPath)
            }
        }
    }

    /// Evaluates rules for a newly added file, returns matching rules
    public static func matchingRules(for fileName: String, in folderPath: String, trigger: String = "file_added") -> [ClawsyRule] {
        guard let manifest = read(for: folderPath) else { return [] }
        return manifest.rules.filter { rule in
            rule.trigger == trigger && matchesGlob(rule.filter, fileName: fileName)
        }
    }

    private static func matchesGlob(_ pattern: String, fileName: String) -> Bool {
        if pattern == "*" { return true }
        // Simple glob: support leading/trailing wildcards
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return fileName.hasSuffix("." + ext)
        }
        return fileName == pattern
    }
}
