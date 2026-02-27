import Cocoa
import FinderSync
import ClawsyShared

class FinderSyncExtension: FIFinderSync {

    override init() {
        super.init()

        // Watch the shared folder (root + subfolders)
        let defaults = UserDefaults(suiteName: "group.ai.openclaw.clawsy")
        let rawPath = defaults?.string(forKey: "sharedFolderPath") ?? "~/Documents/Clawsy"
        let expanded = (rawPath as NSString).expandingTildeInPath
        let root = URL(fileURLWithPath: expanded)

        var watched: Set<URL> = [root]
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for url in contents {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    watched.insert(url)
                }
            }
        }
        FIFinderSyncController.default().directoryURLs = watched
    }

    // MARK: - Toolbar

    override var toolbarItemName: String { "Clawsy" }
    override var toolbarItemToolTip: String { "Clawsy: Ordner mit KI-Agent verbinden" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "Clawsy") ?? NSImage()
    }

    // MARK: - Context Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        let ruleItem = NSMenuItem(
            title: NSLocalizedString("FINDERSYNC_RULES", comment: "Regeln für diesen Ordner..."),
            action: #selector(openRuleEditor),
            keyEquivalent: ""
        )
        ruleItem.image = NSImage(systemSymbolName: "list.bullet.rectangle.fill", accessibilityDescription: nil)
        menu.addItem(ruleItem)

        let statusItem = NSMenuItem(
            title: NSLocalizedString("FINDERSYNC_SEND_STATUS", comment: "Status & Telemetrie senden"),
            action: #selector(sendTelemetry),
            keyEquivalent: ""
        )
        statusItem.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil)
        menu.addItem(statusItem)

        menu.addItem(.separator())

        let runItem = NSMenuItem(
            title: NSLocalizedString("FINDERSYNC_RUN_ACTIONS", comment: "Ordner-Aktionen ausführen"),
            action: #selector(runActions),
            keyEquivalent: ""
        )
        runItem.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)
        menu.addItem(runItem)

        return menu
    }

    // MARK: - Actions

    @objc func openRuleEditor() {
        let folderPath = targetFolderPath()
        ActionBridge.postAction(PendingAction(kind: "open_rule_editor", folderPath: folderPath))
    }

    @objc func sendTelemetry() {
        let folderPath = targetFolderPath()
        ActionBridge.postAction(PendingAction(kind: "send_telemetry", folderPath: folderPath))
    }

    @objc func runActions() {
        let folderPath = targetFolderPath()
        ActionBridge.postAction(PendingAction(kind: "run_actions", folderPath: folderPath))
    }

    // MARK: - Helpers

    private func targetFolderPath() -> String {
        // Try to get the selected/targeted item from the controller
        if let target = FIFinderSyncController.default().targetedURL() {
            return target.path
        }
        // Fall back to the first selected item
        if let items = FIFinderSyncController.default().selectedItemURLs(),
           let first = items.first {
            // If it's a file, use its parent folder
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir), isDir.boolValue {
                return first.path
            }
            return first.deletingLastPathComponent().path
        }
        // Fall back to shared folder root
        let defaults = UserDefaults(suiteName: "group.ai.openclaw.clawsy")
        let raw = defaults?.string(forKey: "sharedFolderPath") ?? "~/Documents/Clawsy"
        return (raw as NSString).expandingTildeInPath
    }
}
