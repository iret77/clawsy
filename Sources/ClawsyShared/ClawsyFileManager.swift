import Foundation

public class ClawsyFileManager {
    
    public struct FileEntry: Codable {
        public let name: String
        public let isDirectory: Bool
        public let size: Int64
        public let modified: Date
        
        public init(name: String, isDirectory: Bool, size: Int64, modified: Date) {
            self.name = name
            self.isDirectory = isDirectory
            self.size = size
            self.modified = modified
        }
    }
    
    public static func folderExists(at path: String) -> Bool {
        let fileManager = Foundation.FileManager.default
        let expandedPath = path.replacingOccurrences(of: "~", with: NSHomeDirectory())
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir) && isDir.boolValue
    }
    
    public static func listFiles(at path: String, subPath: String = "", recursive: Bool = false) -> [FileEntry] {
        let fileManager = Foundation.FileManager.default
        let expandedBasePath = path.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let targetPath: String
        if subPath.isEmpty {
            targetPath = expandedBasePath
        } else {
            // Validate subPath stays within sandbox
            guard let validated = sandboxedPath(base: expandedBasePath, relativePath: subPath) else {
                return []
            }
            targetPath = validated
        }
        let url = URL(fileURLWithPath: targetPath)
        
        if recursive {
            return listFilesRecursive(fileManager: fileManager, baseURL: URL(fileURLWithPath: expandedBasePath), directoryURL: url, prefix: subPath, currentDepth: 0, maxDepth: 5)
        }
        
        do {
            let resourceKeys: [URLResourceKey] = [.nameKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            let items = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])
            
            return items.compactMap { item in
                do {
                    let values = try item.resourceValues(forKeys: Set(resourceKeys))
                    let name = values.name ?? item.lastPathComponent
                    let relativeName = subPath.isEmpty ? name : (subPath as NSString).appendingPathComponent(name)
                    return FileEntry(
                        name: relativeName,
                        isDirectory: values.isDirectory ?? false,
                        size: Int64(values.fileSize ?? 0),
                        modified: values.contentModificationDate ?? Date()
                    )
                } catch {
                    return nil
                }
            }
        } catch {
            return []
        }
    }
    
    private static func listFilesRecursive(fileManager: Foundation.FileManager, baseURL: URL, directoryURL: URL, prefix: String, currentDepth: Int, maxDepth: Int) -> [FileEntry] {
        guard currentDepth <= maxDepth else { return [] }
        
        let resourceKeys: [URLResourceKey] = [.nameKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let items = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else {
            return []
        }
        
        var results: [FileEntry] = []
        for item in items {
            guard let values = try? item.resourceValues(forKeys: Set(resourceKeys)) else { continue }
            let name = values.name ?? item.lastPathComponent
            let relativeName = prefix.isEmpty ? name : (prefix as NSString).appendingPathComponent(name)
            let isDir = values.isDirectory ?? false
            
            results.append(FileEntry(
                name: relativeName,
                isDirectory: isDir,
                size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate ?? Date()
            ))
            
            if isDir {
                let children = listFilesRecursive(fileManager: fileManager, baseURL: baseURL, directoryURL: item, prefix: relativeName, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                results.append(contentsOf: children)
            }
        }
        return results
    }
    
    public static func readFile(at path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }
    
    public static func writeFile(at path: String, base64Content: String) -> Bool {
        guard let data = Data(base64Encoded: base64Content) else { return false }
        let url = URL(fileURLWithPath: path)
        
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    public static func createDirectory(at path: String) -> Bool {
        let fileManager = Foundation.FileManager.default
        let url = URL(fileURLWithPath: path)
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            return false
        }
    }
    
    public static func deleteFile(at path: String) -> Bool {
        let fileManager = Foundation.FileManager.default
        let url = URL(fileURLWithPath: path)
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
    
    public static func renameFile(at path: String, to newName: String) -> Bool {
        let fileManager = Foundation.FileManager.default
        let url = URL(fileURLWithPath: path)
        let newUrl = url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try fileManager.moveItem(at: url, to: newUrl)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Path Sandboxing

    /// Resolves a relative path against the base directory and validates it stays within the sandbox.
    /// Returns the resolved absolute path, or nil if the path escapes the base directory.
    public static func sandboxedPath(base: String, relativePath: String) -> String? {
        let baseURL = URL(fileURLWithPath: base).standardized
        let resolvedURL = baseURL.appendingPathComponent(relativePath).standardized
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        let resolvedPath = resolvedURL.path
        // The resolved path must start with the base path, or be exactly the base path (without trailing slash)
        guard resolvedPath == baseURL.path || resolvedPath.hasPrefix(basePath) else {
            return nil
        }
        return resolvedPath
    }

    // MARK: - File Operation Errors

    public enum MoveError: Error, CustomStringConvertible {
        case sourceNotFound
        case destinationExists
        case pathTraversal
        case moveFailed(String)

        public var description: String {
            switch self {
            case .sourceNotFound: return "Source file or directory not found"
            case .destinationExists: return "Destination already exists"
            case .pathTraversal: return "Path must stay within the shared folder"
            case .moveFailed(let reason): return "Move failed: \(reason)"
            }
        }
    }

    // MARK: - Move File/Directory

    /// Moves a file or directory within the shared folder.
    /// Both source and destination are validated to stay within baseDir.
    /// Intermediate directories at the destination are created automatically.
    public static func moveFile(baseDir: String, source: String, destination: String) -> Result<Void, MoveError> {
        let fileManager = Foundation.FileManager.default

        guard let sourcePath = sandboxedPath(base: baseDir, relativePath: source) else {
            return .failure(.pathTraversal)
        }
        guard let destPath = sandboxedPath(base: baseDir, relativePath: destination) else {
            return .failure(.pathTraversal)
        }

        guard fileManager.fileExists(atPath: sourcePath) else {
            return .failure(.sourceNotFound)
        }
        if fileManager.fileExists(atPath: destPath) {
            return .failure(.destinationExists)
        }

        // Create intermediate directories at destination (mkdir -p)
        let destParent = (destPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: destParent) {
            do {
                try fileManager.createDirectory(atPath: destParent, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return .failure(.moveFailed("Failed to create destination directory: \(error.localizedDescription)"))
            }
        }

        do {
            try fileManager.moveItem(atPath: sourcePath, toPath: destPath)
            return .success(())
        } catch {
            return .failure(.moveFailed(error.localizedDescription))
        }
    }

    // MARK: - Copy File/Directory

    /// Copies a file or directory within the shared folder.
    /// Both source and destination are validated to stay within baseDir.
    /// Intermediate directories at the destination are created automatically.
    public static func copyFile(baseDir: String, source: String, destination: String) -> Result<Void, MoveError> {
        let fileManager = Foundation.FileManager.default

        guard let sourcePath = sandboxedPath(base: baseDir, relativePath: source) else {
            return .failure(.pathTraversal)
        }
        guard let destPath = sandboxedPath(base: baseDir, relativePath: destination) else {
            return .failure(.pathTraversal)
        }

        guard fileManager.fileExists(atPath: sourcePath) else {
            return .failure(.sourceNotFound)
        }
        if fileManager.fileExists(atPath: destPath) {
            return .failure(.destinationExists)
        }

        let destParent = (destPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: destParent) {
            do {
                try fileManager.createDirectory(atPath: destParent, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return .failure(.moveFailed("Failed to create destination directory: \(error.localizedDescription)"))
            }
        }

        do {
            try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
            return .success(())
        } catch {
            return .failure(.moveFailed("Copy failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Rename with Sandboxing

    /// Renames a file or directory within the shared folder.
    /// The new name must be a plain filename (no path separators).
    /// Both old and new paths are validated to stay within baseDir.
    public static func renameFile(baseDir: String, path: String, newName: String) -> Result<Void, MoveError> {
        // newName must not contain path separators
        guard !newName.contains("/") && !newName.contains("..") else {
            return .failure(.pathTraversal)
        }

        guard let sourcePath = sandboxedPath(base: baseDir, relativePath: path) else {
            return .failure(.pathTraversal)
        }

        let parentDir = (sourcePath as NSString).deletingLastPathComponent
        let destPath = (parentDir as NSString).appendingPathComponent(newName)

        // Validate destination stays in sandbox
        let baseURL = URL(fileURLWithPath: baseDir).standardized
        let destURL = URL(fileURLWithPath: destPath).standardized
        let basePth = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        guard destURL.path == baseURL.path || destURL.path.hasPrefix(basePth) else {
            return .failure(.pathTraversal)
        }

        let fileManager = Foundation.FileManager.default
        guard fileManager.fileExists(atPath: sourcePath) else {
            return .failure(.sourceNotFound)
        }
        if fileManager.fileExists(atPath: destPath) {
            return .failure(.destinationExists)
        }

        do {
            try fileManager.moveItem(atPath: sourcePath, toPath: destPath)
            return .success(())
        } catch {
            return .failure(.moveFailed("Rename failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - File Stat

    /// Returns metadata for a file or directory within the shared folder.
    public static func statFile(baseDir: String, relativePath: String) -> [String: Any] {
        guard let fullPath = sandboxedPath(base: baseDir, relativePath: relativePath) else {
            return ["exists": false, "error": "Path must stay within the shared folder"]
        }

        let fileManager = Foundation.FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else {
            return ["exists": false]
        }

        let url = URL(fileURLWithPath: fullPath)
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .creationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return ["exists": true, "isDirectory": isDir.boolValue]
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var result: [String: Any] = [
            "exists": true,
            "isDirectory": isDir.boolValue,
            "size": Int64(values.fileSize ?? 0)
        ]
        if let modified = values.contentModificationDate {
            result["modified"] = formatter.string(from: modified)
        }
        if let created = values.creationDate {
            result["created"] = formatter.string(from: created)
        }
        return result
    }

    // MARK: - File Exists

    /// Quick existence check for a path within the shared folder.
    public static func existsFile(baseDir: String, relativePath: String) -> [String: Any] {
        guard let fullPath = sandboxedPath(base: baseDir, relativePath: relativePath) else {
            return ["exists": false, "error": "Path must stay within the shared folder"]
        }

        let fileManager = Foundation.FileManager.default
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: fullPath, isDirectory: &isDir)
        return ["exists": exists, "isDirectory": exists ? isDir.boolValue : false]
    }

    // MARK: - Glob Pattern Matching

    /// Returns true if the pattern contains glob characters (* or ?).
    public static func isGlobPattern(_ pattern: String) -> Bool {
        return pattern.contains("*") || pattern.contains("?")
    }

    /// Matches a filename against a glob pattern using * and ? wildcards.
    /// * matches zero or more characters (except /).
    /// ? matches exactly one character (except /).
    public static func globMatch(pattern: String, filename: String) -> Bool {
        // Use NSPredicate LIKE which supports * and ? natively
        let predicate = NSPredicate(format: "SELF LIKE %@", pattern)
        return predicate.evaluate(with: filename)
    }

    /// Resolves a glob pattern against the shared folder contents.
    /// The pattern's directory part is used as the search directory.
    /// Returns an array of relative paths (relative to baseDir) that match.
    /// Returns nil if the pattern escapes the sandbox.
    public static func resolveGlob(baseDir: String, pattern: String) -> [String]? {
        let dirPart = (pattern as NSString).deletingLastPathComponent
        let filePattern = (pattern as NSString).lastPathComponent

        // Determine the search directory
        let searchDir: String
        if dirPart.isEmpty {
            searchDir = ""
        } else {
            // Validate the directory part stays in sandbox
            guard sandboxedPath(base: baseDir, relativePath: dirPart) != nil else {
                return nil
            }
            searchDir = dirPart
        }

        let baseDirExpanded = baseDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let searchPath = searchDir.isEmpty ? baseDirExpanded : (baseDirExpanded as NSString).appendingPathComponent(searchDir)
        let searchURL = URL(fileURLWithPath: searchPath)

        let fileManager = Foundation.FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(at: searchURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }

        var matches: [String] = []
        for item in items {
            let name = item.lastPathComponent
            if globMatch(pattern: filePattern, filename: name) {
                let relativePath = searchDir.isEmpty ? name : (searchDir as NSString).appendingPathComponent(name)
                // Validate each match stays in sandbox
                if sandboxedPath(base: baseDir, relativePath: relativePath) != nil {
                    matches.append(relativePath)
                }
            }
        }
        return matches
    }
}
