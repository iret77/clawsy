import SwiftUI
import AppKit

struct FileSyncRequestWindow: View {
    let filename: String
    let operation: String // "Upload" or "Download"
    let onConfirm: (TimeInterval?) -> Void // Optional duration in seconds
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
                        Text(LocalizedStringKey("FILE_SYNC_REQUEST"))
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
                    Text(String(format: NSLocalizedString("AGENT_WANTS_TO", comment: ""), operation.lowercased()))
                        .font(.system(size: 13))
                    Text(String(format: NSLocalizedString("LOCATION", comment: ""), "~/Documents/Clawsy/\(filename)"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(30)
                .frame(maxHeight: .infinity)
                
                Divider().opacity(0.3)
                
                HStack(spacing: 12) {
                    Button(LocalizedStringKey("DENY")) { onCancel() }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(6)
                    
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
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    
                    Button(String(format: NSLocalizedString("ALLOW", comment: ""), operation)) { onConfirm(nil) }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .padding(20)
            }
        }
        .frame(width: 440, height: 280)
    }
}
