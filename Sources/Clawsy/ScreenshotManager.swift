import Foundation
import AppKit

class ScreenshotManager {
    
    static func takeScreenshot(interactive: Bool = false) -> String? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("clawsy_snap.png")
        let path = tempURL.path
        
        // Remove existing
        try? FileManager.default.removeItem(atPath: path)
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        
        var args = ["-x"] // No sound
        
        if interactive {
            args.append("-i") // Interactive mode
        }
        
        // Add output path
        args.append(path)
        task.arguments = args
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Check if file exists (user might have cancelled interactive mode with ESC)
            if FileManager.default.fileExists(atPath: path) {
                let data = try Data(contentsOf: tempURL)
                try? FileManager.default.removeItem(atPath: path) // Cleanup
                return data.base64EncodedString()
            } else {
                print("Screenshot cancelled by user or failed")
                return nil
            }
        } catch {
            print("Failed to run screencapture: \(error)")
            return nil
        }
    }
}
