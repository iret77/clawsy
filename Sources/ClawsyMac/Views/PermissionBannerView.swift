import SwiftUI

/// Inline banner for the main menu popover when required permissions are missing.
/// Each missing permission gets its own row with a clear user-facing description
/// of what the permission enables and a direct button to open System Settings.
/// Modeled after the OpenClaw Mac app's PermissionsSettings pattern.
struct PermissionBannerView: View {
    @ObservedObject var permissionMonitor: PermissionMonitor

    var body: some View {
        let missing = permissionMonitor.missingRequired

        VStack(alignment: .leading, spacing: 10) {
            ForEach(missing) { perm in
                HStack(spacing: 10) {
                    Image(systemName: perm.icon)
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("PERM_BANNER_\(perm.settingsKey)_TITLE", bundle: .clawsy, comment: ""))
                            .font(ClawsyTheme.Font.bannerTitle)
                            .foregroundColor(.primary)

                        Text(NSLocalizedString("PERM_BANNER_\(perm.settingsKey)_DESC", bundle: .clawsy, comment: ""))
                            .font(ClawsyTheme.Font.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(NSLocalizedString("PERM_BANNER_OPEN_SETTINGS", bundle: .clawsy, comment: "")) {
                        permissionMonitor.openSettings(for: perm)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(ClawsyTheme.Spacing.cornerRadius)
    }
}
