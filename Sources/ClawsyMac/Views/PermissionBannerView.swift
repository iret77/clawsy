import SwiftUI

/// Inline banner for the main menu popover when required permissions are missing.
/// Matches the style of ConnectionFailureBanner — standard Clawsy banner pattern.
/// Shows which permissions are missing and provides a direct "Fix" action.
struct PermissionBannerView: View {
    @ObservedObject var permissionMonitor: PermissionMonitor

    var body: some View {
        let missing = permissionMonitor.missingRequired

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield")
                    .font(ClawsyTheme.Font.menuItem)
                    .foregroundColor(.orange)
                    .accessibilityLabel(NSLocalizedString("PERM_BANNER_TITLE", bundle: .clawsy, comment: ""))

                Text(NSLocalizedString("PERM_BANNER_TITLE", bundle: .clawsy, comment: ""))
                    .font(ClawsyTheme.Font.bannerTitle)
                    .foregroundColor(.primary)
            }

            Text(missingDescription(missing))
                .font(ClawsyTheme.Font.bannerBody)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(missing) { perm in
                    Button(action: { permissionMonitor.openSettings(for: perm) }) {
                        Label(perm.rawValue, systemImage: perm.icon)
                            .font(ClawsyTheme.Font.bannerBody)
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

    private func missingDescription(_ missing: [ClawsyPermission]) -> String {
        let names = missing.map { $0.rawValue }
        if names.count == 1 {
            return String(format: NSLocalizedString("PERM_BANNER_DESC_SINGLE", bundle: .clawsy, comment: ""), names[0])
        }
        return String(format: NSLocalizedString("PERM_BANNER_DESC_MULTI", bundle: .clawsy, comment: ""), names.joined(separator: ", "))
    }
}
