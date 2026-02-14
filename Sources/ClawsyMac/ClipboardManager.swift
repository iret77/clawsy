import Foundation
import AppKit

class ClipboardManager {
    
    static func getClipboardContent() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }
    
    static func setClipboardContent(_ content: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
    }
}
