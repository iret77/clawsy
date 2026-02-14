import SwiftUI
import AVFoundation

struct CameraPreviewView: View {
    let image: NSImage
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("CAMERA_PREVIEW_TITLE")
                .font(.headline)
            
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 300)
                .cornerRadius(8)
                .shadow(radius: 4)
            
            HStack(spacing: 20) {
                Button("ALERT_DENY") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("SEND_TO_AGENT") {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
