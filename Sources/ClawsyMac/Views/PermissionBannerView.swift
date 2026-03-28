import SwiftUI

/// Permission banner for the main menu popover.
/// Icon + title/description stacked + action button per row.
/// Camera/Notifications: "Grant" (native dialog). Others: "Settings" (deep-link).
struct PermissionBannerView: View {
    @ObservedObject var permissionMonitor: PermissionMonitor

    var body: some View {
        let missing = permissionMonitor.missingRequired

        VStack(spacing: 8) {
            ForEach(missing) { perm in
                HStack(spacing: 8) {
                    Image(systemName: perm.icon)
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(perm.displayName)
                            .font(ClawsyTheme.Font.bannerTitle)
                            .foregroundColor(.primary)

                        Text(perm.description)
                            .font(ClawsyTheme.Font.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 4)

                    if perm.hasNativeGrant {
                        Button(NSLocalizedString("PERM_GRANT", bundle: .clawsy, comment: "")) {
                            permissionMonitor.requestPermission(perm)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button(NSLocalizedString("PERM_BANNER_OPEN_SETTINGS", bundle: .clawsy, comment: "")) {
                            permissionMonitor.openSettings(for: perm)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(ClawsyTheme.Spacing.cornerRadius)
    }
}
