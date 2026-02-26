import Foundation
import AppKit
import UserNotifications

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    @Published var updateAvailable: Bool = false
    @Published var updateVersion: String = ""
    @Published var downloadProgress: Double = 0.0
    @Published var isChecking: Bool = false
    
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
    
    /// Request notification permission independently (may run before NetworkManager).
    private func ensureNotificationPermission() {
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

    func installUpdate(at newAppPath: String) {
        let targetPath = Bundle.main.bundlePath
        let scriptPath = "/tmp/clawsy_updater.sh"
        let launchdLabel = "ai.clawsy.updater"
        
        print("🔄 Preparing update: '\(newAppPath)' → '\(targetPath)'")
        
        // Generate the update script inline (no bundled resource needed).
        // The script waits for the app to quit, swaps the bundle, and relaunches.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let plistPath = "\(home)/Library/LaunchAgents/\(launchdLabel).plist"
        
        let script = """
        #!/bin/bash
        sleep 2
        rm -rf "\(targetPath)"
        mv "\(newAppPath)" "\(targetPath)"
        xattr -cr "\(targetPath)"
        open "\(targetPath)"
        launchctl remove \(launchdLabel) 2>/dev/null
        rm -f \(scriptPath)
        rm -f \(plistPath)
        """
        
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        } catch {
            print("❌ Failed to write update script: \(error)")
            return
        }
        
        // Strategy 1: `launchctl submit` — schedules a launchd job outside the sandbox
        let submitted = launchctlSubmit(label: launchdLabel, scriptPath: scriptPath)
        
        if !submitted {
            // Strategy 2: Write a LaunchAgent plist and load it
            print("⚠️ launchctl submit failed, falling back to LaunchAgent plist...")
            let plistLoaded = loadLaunchAgentPlist(label: launchdLabel, scriptPath: scriptPath)
            if !plistLoaded {
                print("❌ Both launchctl strategies failed. Update aborted.")
                return
            }
        }
        
        print("🚀 Update scheduled. Terminating app...")
        NSApp.terminate(nil)
    }
    
    /// Try `launchctl submit -l <label> -- /bin/bash <script>`.
    /// Returns `true` if the process launched without error.
    private func launchctlSubmit(label: String, scriptPath: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["submit", "-l", label, "--", "/bin/bash", scriptPath]
        
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                print("✅ launchctl submit succeeded")
                return true
            } else {
                print("⚠️ launchctl submit exited with status \(proc.terminationStatus)")
                return false
            }
        } catch {
            print("⚠️ launchctl submit threw: \(error)")
            return false
        }
    }
    
    /// Write a LaunchAgent plist to ~/Library/LaunchAgents and load it.
    /// Returns `true` on success.
    private func loadLaunchAgentPlist(label: String, scriptPath: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let agentsDir = "\(home)/Library/LaunchAgents"
        let plistPath = "\(agentsDir)/\(label).plist"
        
        // Ensure ~/Library/LaunchAgents exists
        try? FileManager.default.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
        
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(scriptPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
        
        do {
            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Failed to write LaunchAgent plist: \(error)")
            return false
        }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["load", plistPath]
        
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                print("✅ LaunchAgent plist loaded")
                return true
            } else {
                print("⚠️ launchctl load exited with status \(proc.terminationStatus)")
                return false
            }
        } catch {
            print("❌ launchctl load threw: \(error)")
            return false
        }
    }
}
