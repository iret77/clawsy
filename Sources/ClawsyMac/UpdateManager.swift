import Foundation
import AppKit

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    @Published var updateAvailable: Bool = false
    @Published var updateVersion: String = ""
    @Published var downloadProgress: Double = 0.0
    
    private let githubRepo = "iret77/clawsy"
    
    func checkForUpdates(channel: String = "release") {
        // Mocking the check for now - normally would hit GitHub API
        // In a real implementation: fetch releases, compare versions
        print("Checking for updates on channel: \(channel)")
    }
    
    func installUpdate(at path: String) {
        let scriptPath = Bundle.main.path(forResource: "update_installer", ofType: "sh") ?? "/tmp/update_installer.sh"
        let targetPath = Bundle.main.bundlePath
        
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [scriptPath, path, targetPath]
        
        try? task.run()
        NSApp.terminate(nil)
    }
}
