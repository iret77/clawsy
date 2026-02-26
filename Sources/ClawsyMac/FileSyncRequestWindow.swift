import SwiftUI
import AppKit

struct FileSyncRequestWindow: View {
    let filename: String
    let operation: String // "Upload" or "Download"
    let onConfirm: (TimeInterval?) -> Void // Optional duration in seconds
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: operation == "Upload" ? "arrow.up.doc.fill" : "arrow.down.doc.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 4, y: 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey("FILE_SYNC_REQUEST"))
                        .font(.system(size: 15, weight: .bold))
                    Text("\(operation): \(filename)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider().opacity(0.3)
            
            // Content
            VStack(spacing: 12) {
                Text(String(format: NSLocalizedString("AGENT_WANTS_TO", comment: ""), operation.lowercased()))
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                
                Text(String(format: NSLocalizedString("LOCATION", comment: ""), "~/Documents/Clawsy/\(filename)"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
            .frame(maxHeight: .infinity)
            
            Divider().opacity(0.3)
            
            // Footer Action Bar
            HStack(spacing: 12) {
                Button(LocalizedStringKey("DENY")) { onCancel() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                    .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Menu("Allow...") {
                    Button(LocalizedStringKey("ALLOW_ONCE")) { onConfirm(nil) }
                    Button(LocalizedStringKey("ALLOW_1H")) { onConfirm(3600) }
                    Button(LocalizedStringKey("ALLOW_DAY")) {
                        let now = Date()
                        let calendar = Calendar.current
                        if let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) {
                            let seconds = endOfDay.timeIntervalSince(now)
                            onConfirm(seconds)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                Button(String(format: NSLocalizedString("ALLOW", comment: ""), operation)) { onConfirm(nil) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.03))
        }
        .frame(width: 440, height: 260)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}
