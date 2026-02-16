import Foundation

public class ShareHandler {
    
    public enum ShareError: Error {
        case noData
        case failedToSend
    }
    
    public static func handleSharedItems(_ items: [NSExtensionItem], network: NetworkManager, completion: @escaping (Result<Void, Error>) -> Void) {
        var sharedText = ""
        var sharedURLs: [URL] = []
        var sharedFiles: [[String: Any]] = []
        
        let group = DispatchGroup()
        
        for item in items {
            guard let attachments = item.attachments else { continue }
            
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { (item, error) in
                        if let text = item as? String {
                            sharedText += text + "\n"
                        }
                        group.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier("public.url") {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: "public.url", options: nil) { (item, error) in
                        if let url = item as? URL {
                            if url.isFileURL {
                                // Handle File
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
                    // Generic fallback for files that don't match public.url (like some images or PDFs)
                    group.enter()
                    provider.loadItem(forTypeIdentifier: "public.item", options: nil) { (item, error) in
                        if let url = item as? URL, url.isFileURL {
                            if let data = try? Data(contentsOf: url) {
                                sharedFiles.append([
                                    "name": url.lastPathComponent,
                                    "content": data.base64EncodedString(),
                                    "type": "file"
                                ])
                            }
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
            
            network.sendOneShot(kind: "share", payload: finalContent) { success in
                if success {
                    completion(.success(()))
                } else {
                    completion(.failure(ShareError.failedToSend))
                }
            }
        }
    }
}
