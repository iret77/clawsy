import Foundation
import AppKit
import UserNotifications

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    @Published var updateAvailable: Bool = false
    @Published var updateVersion: String = ""
    @Published var downloadProgress: Double = 0.0
    @Published var isChecking: Bool = false
    @Published var isInstalling: Bool = false
    
    private let githubRepo = "iret77/clawsy"
    private var periodicTimer: Timer?
    
    /// Interval for automatic background update checks (4 hours)
    private let checkInterval: TimeInterval = 4 * 60 * 60
    
    /// Track last version we sent a notification for to avoid spamming
    private var lastNotifiedVersion: String {
        get { UserDefaults.standard.string(forKey: "lastNotifiedUpdateVersion") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastNotifiedUpdateVersion") }
    }
    
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
    
    // MARK: - Periodic Checks
    
    /// Start a repeating timer that checks for updates every 4 hours.
    /// Safe to call multiple times — will not create duplicate timers.
    func startPeriodicChecks() {
        guard periodicTimer == nil else { return }
        periodicTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdates(silent: true)
        }
        // Keep timer alive even when the run loop is tracking UI events
        if let timer = periodicTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        print("🔄 Periodic update checks started (every 4h)")
    }
    
    // MARK: - Notification Permission
    
    /// Request notification permission independently (may run before connection).
    func ensureNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("⚠️ Notification permission error: \(error)")
            }
        }
    }
    
    // MARK: - Update Check
    
    /// Check for updates.
    /// - Parameters:
    ///   - silent: If `true`, this is an automatic background check — show a macOS notification when an update is found.
    ///             If `false` (default), this is a manual user-triggered check — only update the published properties (no notification).
    ///   - channel: Release channel (currently unused, reserved for future beta/stable split).
    func checkForUpdates(silent: Bool = false, channel: String = "release") {
        print("🔍 Checking for updates (silent: \(silent), channel: \(channel))...")
        DispatchQueue.main.async { self.isChecking = true }
        
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        let request = URLRequest(url: url)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.isChecking = false }
            
            guard let self = self else { return }
            
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
                
                if self.isVersion(remote, newerThan: local) {
                    DispatchQueue.main.async {
                        print("✅ Update found: \(release.tagName)")
                        self.updateAvailable = true
                        self.updateVersion = release.tagName
                    }
                    
                    // Fire macOS notification only for automatic (silent) checks
                    // and only if we haven't already notified for this version
                    if silent && self.lastNotifiedVersion != release.tagName {
                        self.sendUpdateNotification(version: release.tagName)
                        self.lastNotifiedVersion = release.tagName
                    }
                } else {
                    print("✅ Clawsy is up to date.")
                }
            } catch {
                print("❌ JSON Decode error: \(error)")
            }
        }.resume()
    }
    
    // MARK: - macOS Notification
    
    private func sendUpdateNotification(version: String) {
        ensureNotificationPermission()
        
        let content = UNMutableNotificationContent()
        content.title = "Clawsy Update verfügbar"
        content.body = "Version \(version) ist bereit. Einstellungen öffnen zum Installieren."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "clawsy-update-\(version)",
            content: content,
            trigger: nil  // deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send update notification: \(error)")
            } else {
                print("🔔 Update notification sent for \(version)")
            }
        }
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
        
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/tags/\(updateVersion)")!
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
    
    /// Active download session & delegate — stored as instance vars so ARC doesn't release them.
    private var downloadDelegate: DownloadDelegate?
    private var downloadSession: URLSession?

    private func downloadAsset(url: URL, filename: String) {
        DispatchQueue.main.async { self.isInstalling = true; self.downloadProgress = 0.0 }

        let delegate = DownloadDelegate(
            filename: filename,
            onProgress: { [weak self] fraction in
                DispatchQueue.main.async {
                    self?.downloadProgress = min(fraction * 0.9, 0.9)
                }
            },
            onComplete: { [weak self] localURL, error in
                guard let self = self else { return }
                guard let localURL = localURL, error == nil else {
                    print("❌ Download failed: \(error?.localizedDescription ?? "Unknown")")
                    DispatchQueue.main.async { self.isInstalling = false }
                    return
                }

                let fileManager = FileManager.default
                let destURL = fileManager.temporaryDirectory.appendingPathComponent(filename)

                do {
                    if fileManager.fileExists(atPath: destURL.path) {
                        try fileManager.removeItem(at: destURL)
                    }
                    try fileManager.moveItem(at: localURL, to: destURL)
                    DispatchQueue.main.async { self.downloadProgress = 0.9 }
                    print("✅ Downloaded to: \(destURL.path)")
                    self.unzipAndInstall(fileURL: destURL)
                } catch {
                    print("❌ File move error: \(error)")
                    DispatchQueue.main.async { self.isInstalling = false }
                }
            }
        )

        self.downloadDelegate = delegate
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.downloadSession = session
        session.downloadTask(with: url).resume()
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

    func installUpdate(at newAppPath: String) {
        let targetPath = Bundle.main.bundlePath
        let scriptPath = "/tmp/clawsy_updater.sh"

        print("🔄 Installing update: '\(newAppPath)' → '\(targetPath)'")

        // Write the update script to /tmp.
        // The child bash process is started before NSApp.terminate — when the
        // parent app exits its sandbox is torn down, allowing the orphaned bash
        // process to replace the app bundle and relaunch cleanly.
        let script = """
        #!/bin/sh
        sleep 2
        rm -rf "\(targetPath)"
        mv "\(newAppPath)" "\(targetPath)"
        xattr -cr "\(targetPath)"
        open "\(targetPath)"
        rm -f \(scriptPath)
        """

        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        } catch {
            print("❌ Failed to write update script: \(error)")
            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(string: "https://github.com/\(self.githubRepo)/releases/latest")!)
                self.isInstalling = false
            }
            return
        }

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            print("❌ Update script not found at \(scriptPath) after write")
            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(string: "https://github.com/\(self.githubRepo)/releases/latest")!)
                self.isInstalling = false
            }
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath]

        do {
            try task.run()
        } catch {
            print("❌ Failed to launch update script: \(error)")
            // Fallback: open GitHub releases page so user can install manually
            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(string: "https://github.com/iret77/clawsy/releases/latest")!)
                self.isInstalling = false
            }
            return
        }

        print("🚀 Update script running. Terminating app...")
        NSApp.terminate(nil)
    }
}

// MARK: - URLSessionDownloadDelegate for live progress

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let filename: String
    let onProgress: (Double) -> Void
    let onComplete: (URL?, Error?) -> Void

    init(filename: String, onProgress: @escaping (Double) -> Void, onComplete: @escaping (URL?, Error?) -> Void) {
        self.filename = filename
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onComplete(location, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onComplete(nil, error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(fraction)
    }
}
