import SwiftUI

/// Inline banner for the main menu popover when required permissions are missing.
/// Each permission row adapts its button to macOS capabilities:
/// - Camera/Notifications: "Grant" triggers a native one-click Allow dialog
/// - Accessibility/Screen Recording: "Open Settings" deep-links to the right pane
///   (macOS does not offer one-click grant for these)
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
                        Text(perm.displayName)
                            .font(ClawsyTheme.Font.bannerTitle)
                            .foregroundColor(.primary)

                        Text(perm.description)
                            .font(ClawsyTheme.Font.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if perm.hasNativeGrant {
                        // Camera, Notifications — macOS shows a real Allow/Deny dialog
                        Button(NSLocalizedString("PERM_GRANT", bundle: .clawsy, comment: "")) {
                            permissionMonitor.requestPermission(perm)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        // Accessibility, Screen Recording — no native dialog, deep-link to Settings
                        Button(NSLocalizedString("PERM_BANNER_OPEN_SETTINGS", bundle: .clawsy, comment: "")) {
                            permissionMonitor.openSettings(for: perm)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(ClawsyTheme.Spacing.cornerRadius)
    }
}
