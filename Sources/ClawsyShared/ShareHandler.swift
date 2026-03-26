import Foundation

public class ShareHandler {

    public enum ShareError: LocalizedError {
        case noData
        case failedToSend

        public var errorDescription: String? {
            switch self {
            case .noData:
                return NSLocalizedString("SHARE_ERROR_NO_DATA", bundle: .clawsy, comment: "")
            case .failedToSend:
                return NSLocalizedString("SHARE_ERROR_SEND_FAILED", bundle: .clawsy, comment: "")
            }
        }
    }

    /// Handle shared items from the Share Extension. Sends via GatewayPoller REST API.
    public static func handleSharedItems(
        _ items: [NSExtensionItem],
        poller: GatewayPoller,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var sharedText = ""
        var sharedURLs: [URL] = []
        var sharedFiles: [[String: Any]] = []

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
                                        "content": data.base64EncodedString(),
                                        "type": "file"
                                    ])
                                }
                            } else {
                                sharedURLs.append(url)
                            }
                        }
                        group.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier("public.item") {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: "public.item", options: nil) { (item, _) in
                        if let url = item as? URL, url.isFileURL,
                           let data = try? Data(contentsOf: url) {
                            sharedFiles.append([
                                "name": url.lastPathComponent,
                                "content": data.base64EncodedString(),
                                "type": "file"
                            ])
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            var finalContent: [String: Any] = [:]
            if !sharedText.isEmpty {
                finalContent["text"] = sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !sharedURLs.isEmpty {
                finalContent["urls"] = sharedURLs.map { $0.absoluteString }
            }
            if !sharedFiles.isEmpty {
                finalContent["files"] = sharedFiles
            }

            if finalContent.isEmpty {
                completion(.failure(ShareError.noData))
                return
            }

            guard let jsonString = ClawsyEnvelopeBuilder.build(type: "share", content: finalContent) else {
                completion(.failure(ShareError.failedToSend))
                return
            }

            poller.sendEnvelope(jsonString, sessionKey: poller.targetSessionKey)
            completion(.success(()))
        }
    }
}
