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
        
        // Capture stdout and stderr
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            
            // Wait with a reasonable timeout (e.g., 30s) to prevent deadlock
            let timeout: TimeInterval = 30
            let deadline = Date().addingTimeInterval(timeout)
            
            while task.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            if task.isRunning {
                print("screencapture timed out after \(timeout)s. Terminating.")
                task.terminate()
                return nil
            }
            
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errString = String(data: errData, encoding: .utf8), !errString.isEmpty {
                print("screencapture stderr: \(errString)")
            }
            
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
