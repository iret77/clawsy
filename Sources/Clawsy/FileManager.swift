import Foundation
import AppKit

class ClawsyFileManager {
    
    struct FileEntry: Codable {
        let name: String
        let isDirectory: Bool
        let size: Int64
        let modified: Date
    }
    
    static func folderExists(at path: String) -> Bool {
        let fileManager = Foundation.FileManager.default
        let expandedPath = path.replacingOccurrences(of: "~", with: NSHomeDirectory())
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir) && isDir.boolValue
    }
    
    static func listFiles(at path: String) -> [FileEntry] {
        let fileManager = Foundation.FileManager.default
        let url = URL(fileURLWithPath: path)
        
        print("[FileManager] Attempting to list directory: \(path)")
        
        do {
            let resourceKeys: [URLResourceKey] = [.nameKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            let items = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])
            
            print("[FileManager] Found \(items.count) raw items")
            
            return items.compactMap { item in
                do {
                    let values = try item.resourceValues(forKeys: Set(resourceKeys))
                    return FileEntry(
                        name: values.name ?? item.lastPathComponent,
                        isDirectory: values.isDirectory ?? false,
                        size: Int64(values.fileSize ?? 0),
                        modified: values.contentModificationDate ?? Date()
                    )
                } catch {
                    print("[FileManager] Skipping item \(item.lastPathComponent) due to error: \(error)")
                    return nil
                }
            }
        } catch {
            print("[FileManager] Critical error listing directory: \(error)")
            return []
        }
    }
    
    static func readFile(at path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }
    
    static func writeFile(at path: String, base64Content: String) -> Bool {
        guard let data = Data(base64Encoded: base64Content) else { return false }
        let url = URL(fileURLWithPath: path)
        
        do {
            try data.write(to: url)
            return true
        } catch {
            print("Error writing file: \(error)")
            return false
        }
    }
}
