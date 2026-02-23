import Foundation
import AppKit

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    @Published var updateAvailable: Bool = false
    @Published var updateVersion: String = ""
    @Published var downloadProgress: Double = 0.0
    @Published var isChecking: Bool = false
    
    private let githubRepo = "iret77/clawsy"
    
    struct Release: Codable {
        let tagName: String
        let assets: [Asset]
        
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }
    
    struct Asset: Codable {
        let name: String
        let browserDownloadUrl: String
        
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }
    
    func checkForUpdates(channel: String = "release") {
        print("🔍 Checking for updates on channel: \(channel)...")
        DispatchQueue.main.async { self.isChecking = true }
        
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        let request = URLRequest(url: url)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.isChecking = false }
            
            guard let data = data, error == nil else {
                print("❌ Update check failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                let release = try JSONDecoder().decode(Release.self, from: data)
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                
                print("ℹ️ Local: \(currentVersion), Remote: \(release.tagName)")
                
                let remote = release.tagName.replacingOccurrences(of: "v", with: "")
                let local = currentVersion.replacingOccurrences(of: "v", with: "")
                
                if self?.isVersion(remote, newerThan: local) == true {
                    DispatchQueue.main.async {
                        print("✅ Update found: \(release.tagName)")
                        self?.updateAvailable = true
                        self?.updateVersion = release.tagName
                    }
                } else {
                    print("✅ Clawsy is up to date.")
                }
            } catch {
                print("❌ JSON Decode error: \(error)")
            }
        }.resume()
    }
    
    private func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        
        for (r, l) in zip(remoteParts, localParts) {
            if r > l { return true }
            if r < l { return false }
        }
        return remoteParts.count > localParts.count
    }
    
    func downloadAndInstall() {
        guard !updateVersion.isEmpty else { return }
        print("⬇️ Starting download for \(updateVersion)...")
        
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let release = try? JSONDecoder().decode(Release.self, from: data) else { return }
            
            // Prefer .zip, fallback to .dmg
            guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) ?? release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
                print("❌ No suitable asset found.")
                return
            }
            
            self?.downloadAsset(url: URL(string: asset.browserDownloadUrl)!, filename: asset.name)
        }.resume()
    }
    
    private func downloadAsset(url: URL, filename: String) {
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            guard let localURL = localURL, error == nil else {
                print("❌ Download failed: \(error?.localizedDescription ?? "Unknown")")
                return
            }
            
            let fileManager = FileManager.default
            let destURL = fileManager.temporaryDirectory.appendingPathComponent(filename)
            
            do {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.moveItem(at: localURL, to: destURL)
                print("✅ Downloaded to: \(destURL.path)")
                
                self.unzipAndInstall(fileURL: destURL)
            } catch {
                print("❌ File move error: \(error)")
            }
        }
        task.resume()
    }
    
    private func unzipAndInstall(fileURL: URL) {
        let fileManager = FileManager.default
        let extractionDir = fileManager.temporaryDirectory.appendingPathComponent("ClawsyUpdate_\(UUID().uuidString)")
        
        do {
            try fileManager.createDirectory(at: extractionDir, withIntermediateDirectories: true)
            
            print("📦 Unzipping...")
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-q", fileURL.path, "-d", extractionDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
            
            let contents = try fileManager.contentsOfDirectory(at: extractionDir, includingPropertiesForKeys: nil)
            
            // Look for Clawsy.app (or any .app)
            if let appBundle = contents.first(where: { $0.pathExtension == "app" }) {
                print("🚀 Found app bundle: \(appBundle.path). Installing...")
                DispatchQueue.main.async {
                    self.installUpdate(at: appBundle.path)
                }
            } else {
                 // Check for nested folder (some zips have a root folder)
                 if let subDir = contents.first(where: { $0.hasDirectoryPath }),
                   let subContents = try? fileManager.contentsOfDirectory(at: subDir, includingPropertiesForKeys: nil),
                   let nestedApp = subContents.first(where: { $0.pathExtension == "app" }) {
                    print("🚀 Found nested app bundle: \(nestedApp.path). Installing...")
                     DispatchQueue.main.async {
                        self.installUpdate(at: nestedApp.path)
                     }
                 } else {
                     print("❌ Could not find .app bundle in update.")
                 }
            }
            
        } catch {
            print("❌ Unzip/Install error: \(error)")
        }
    }

    func installUpdate(at path: String) {
        let scriptPath = Bundle.main.path(forResource: "update_installer", ofType: "sh") ?? "/tmp/update_installer.sh"
        
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            print("❌ update_installer.sh not found in bundle!")
            return
        }
        
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        
        let targetPath = Bundle.main.bundlePath
        print("🔄 Running installer: \(scriptPath) '\(path)' '\(targetPath)'")
        
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [scriptPath, path, targetPath]
        
        try? task.run()
        NSApp.terminate(nil)
    }
}
