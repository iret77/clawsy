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
        let targetPath = subPath.isEmpty ? expandedBasePath : (expandedBasePath as NSString).appendingPathComponent(subPath)
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

    // MARK: - Move File/Directory

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
}
