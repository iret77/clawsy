import Cocoa
import Social
import ClawsyShared

/// Share Extension — receives shared items and passes them to the main app
/// via App Group container. The main app picks them up and sends via WebSocket.
///
/// Extensions cannot maintain WebSocket connections (too short-lived).
/// Instead we write a pending share file and notify the main app via DNC.
class ShareViewController: NSViewController {

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        let visualEffect = NSVisualEffectView(frame: view.bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        view.addSubview(visualEffect)

        let label = NSTextField(labelWithString: NSLocalizedString("SENDING_TO_OPENCLAW", bundle: .clawsy, comment: ""))
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 140, width: 300, height: 20)
        view.addSubview(label)

        let progress = NSProgressIndicator(frame: NSRect(x: 130, y: 100, width: 40, height: 40))
        progress.style = .spinning
        progress.startAnimation(nil)
        view.addSubview(progress)

        self.view = view
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        guard let items = self.extensionContext?.inputItems as? [NSExtensionItem] else {
            cancel(nil); return
        }

        // Collect shared content
        collectSharedContent(from: items) { [weak self] content in
            guard let self = self else { return }

            if content.isEmpty {
                self.completeWithError(NSError(domain: "ai.clawsy", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("SHARE_ERROR_NO_DATA", bundle: .clawsy, comment: "")]))
                return
            }

            // Write to App Group container for main app to pick up
            if self.writePendingShare(content) {
                // Notify main app via DistributedNotificationCenter
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("ai.clawsy.pendingShare"),
                    object: nil, userInfo: nil, deliverImmediately: true
                )
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } else {
                self.completeWithError(NSError(domain: "ai.clawsy", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("SHARE_ERROR_SEND_FAILED", bundle: .clawsy, comment: "")]))
            }
        }
    }

    // MARK: - Content Collection

    private func collectSharedContent(from items: [NSExtensionItem], completion: @escaping ([String: Any]) -> Void) {
        var sharedText = ""
        var sharedURLs: [String] = []
        var sharedFiles: [[String: String]] = []

        let group = DispatchGroup()

        for item in items {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { (item, _) in
                        if let text = item as? String { sharedText += text + "\n" }
                        group.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier("public.url") {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: "public.url", options: nil) { (item, _) in
                        if let url = item as? URL {
                            if url.isFileURL {
                                if let data = try? Data(contentsOf: url) {
                                    sharedFiles.append([
                                        "name": url.lastPathComponent,
                                        "content": data.base64EncodedString()
                                    ])
                                }
                            } else {
                                sharedURLs.append(url.absoluteString)
                            }
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            var content: [String: Any] = [:]
            if !sharedText.isEmpty {
                content["text"] = sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !sharedURLs.isEmpty { content["urls"] = sharedURLs }
            if !sharedFiles.isEmpty { content["files"] = sharedFiles }
            completion(content)
        }
    }

    // MARK: - App Group Handoff

    private func writePendingShare(_ content: [String: Any]) -> Bool {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConfig.appGroup
        ) else { return false }

        let fileURL = container.appendingPathComponent("pending_share.json")

        let envelope: [String: Any] = [
            "type": "share",
            "version": SharedConfig.shortVersion,
            "localTime": ISO8601DateFormatter().string(from: Date()),
            "content": content
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: []) else { return false }

        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Error Handling

    private func completeWithError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("SHARE_FAILED", bundle: .clawsy, comment: "")
        alert.informativeText = error.localizedDescription
        alert.runModal()
        self.extensionContext?.cancelRequest(withError: error)
    }

    func cancel(_ sender: AnyObject?) {
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        self.extensionContext?.cancelRequest(withError: cancelError)
    }
}
