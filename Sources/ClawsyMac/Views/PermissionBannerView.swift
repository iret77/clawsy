import SwiftUI

/// Compact permission banner for the main menu popover.
/// Each row: icon + title + short description + action button.
/// Camera/Notifications get "Grant" (native dialog), others get "Settings" (deep-link).
struct PermissionBannerView: View {
    @ObservedObject var permissionMonitor: PermissionMonitor

    var body: some View {
        let missing = permissionMonitor.missingRequired

        VStack(spacing: 6) {
            ForEach(missing) { perm in
                HStack(spacing: 8) {
                    Image(systemName: perm.icon)
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                        .frame(width: 18)

                    Text(perm.displayName)
                        .font(ClawsyTheme.Font.bannerTitle)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(perm.description)
                        .font(ClawsyTheme.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if perm.hasNativeGrant {
                        Button(NSLocalizedString("PERM_GRANT", bundle: .clawsy, comment: "")) {
                            permissionMonitor.requestPermission(perm)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    } else {
                        Button(NSLocalizedString("PERM_BANNER_OPEN_SETTINGS", bundle: .clawsy, comment: "")) {
                            permissionMonitor.openSettings(for: perm)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
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
