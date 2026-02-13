import SwiftUI
import AppKit

struct FileSyncRequestWindow: View {
    let filename: String
    let operation: String // "Upload" or "Download"
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: operation == "Upload" ? "arrow.up.doc.fill" : "arrow.down.doc.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("File Sync Request")
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(operation): \(filename)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                Divider().opacity(0.3)
                
                VStack(spacing: 12) {
                    Text("The agent wants to \(operation.lowercased()) a file.")
                        .font(.system(size: 13))
                    Text("Location: ~/Documents/Clawsy/\(filename)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(30)
                .frame(maxHeight: .infinity)
                
                Divider().opacity(0.3)
                
                HStack(spacing: 12) {
                    Spacer()
                    Button("Deny") { onCancel() }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(6)
                    
                    Button("Allow \(operation)") { onConfirm() }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .padding(20)
            }
        }
        .frame(width: 400, height: 280)
    }
}
