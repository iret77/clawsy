import Foundation
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

class ScreenshotManager {
    
    static func takeScreenshot() -> String? {
        // Create an image from the main display
        guard let imageRef = CGDisplayCreateImage(CGMainDisplayID()) else {
            print("Failed to capture screen")
            return nil
        }
        
        let image = NSImage(cgImage: imageRef, size: NSZeroSize)
        
        // Convert to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            print("Failed to convert to PNG")
            return nil
        }
        
        // Base64 encode
        return pngData.base64EncodedString()
    }
}
