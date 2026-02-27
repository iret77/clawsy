import SwiftUI
import AppKit
import ClawsyShared

struct FileSyncRequestWindow: View {
    let filename: String
    let operation: String // "Upload" or "Download" or "Delete"
    let onConfirm: (TimeInterval?) -> Void
    let onCancel: () -> Void

    // Human-readable operation name (localized)
    private var operationLocalized: String {
        switch operation {
        case "Upload":   return NSLocalizedString("OP_UPLOAD", bundle: .clawsy, comment: "")
        case "Download": return NSLocalizedString("OP_DOWNLOAD", bundle: .clawsy, comment: "")
        case "Delete":   return NSLocalizedString("OP_DELETE", bundle: .clawsy, comment: "")
        default:         return operation
        }
    }

    private var operationIcon: String {
        switch operation {
        case "Upload":   return "arrow.up.doc.fill"
        case "Download": return "arrow.down.doc.fill"
        case "Delete":   return "trash.fill"
        default:         return "doc.fill"
        }
    }

    // Hide internal system filenames from the user
    private var displayFilename: String {
        if filename == ".agent_status.json" {
            return NSLocalizedString("FILENAME_AGENT_STATUS", bundle: .clawsy, comment: "")
        }
        return filename
    }

    private var confirmLabel: String {
        switch operation {
        case "Upload":   return NSLocalizedString("ALLOW_UPLOAD", bundle: .clawsy, comment: "")
        case "Download": return NSLocalizedString("ALLOW_DOWNLOAD", bundle: .clawsy, comment: "")
        case "Delete":   return NSLocalizedString("ALLOW_DELETE", bundle: .clawsy, comment: "")
        default:         return NSLocalizedString("ALLOW_GENERIC", bundle: .clawsy, comment: "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: operationIcon)
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: operation == "Delete" ? [.red, .orange] : [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: (operation == "Delete" ? Color.red : Color.blue).opacity(0.3), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FILESYNC_TITLE", bundle: .clawsy)
                        .font(.system(size: 15, weight: .bold))
                    Text("\(operationLocalized): \(displayFilename)")
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
                Text(String(format: NSLocalizedString("AGENT_WANTS_TO_OP", bundle: .clawsy, comment: ""), operationLocalized.lowercased(), displayFilename))
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)

                Text("~/Documents/Clawsy/\(filename == ".agent_status.json" ? "…" : filename)")
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
                Button(action: { onCancel() }) {
                    Label(NSLocalizedString("DENY", bundle: .clawsy, comment: ""), systemImage: "xmark")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Menu(NSLocalizedString("ALLOW_LIMITED", bundle: .clawsy, comment: "")) {
                    Button(LocalizedStringKey("ALLOW_ONCE")) { onConfirm(nil) }
                    Button(LocalizedStringKey("ALLOW_1H"))   { onConfirm(3600) }
                    Button(LocalizedStringKey("ALLOW_DAY"))  {
                        let now = Date()
                        let calendar = Calendar.current
                        if let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) {
                            onConfirm(endOfDay.timeIntervalSince(now))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)

                Button(action: { onConfirm(nil) }) {
                    Label(confirmLabel, systemImage: operationIcon)
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(operation == "Delete" ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.03))
        }
        .frame(width: 440, height: 260)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }
}
