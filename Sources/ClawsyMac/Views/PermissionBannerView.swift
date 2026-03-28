import SwiftUI

/// Inline banner for the main menu popover when required permissions are missing.
/// Each missing permission gets its own row with a clear description and a single
/// "Grant" button that triggers the native macOS permission dialog directly —
/// no manual navigation to System Settings needed.
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

                    Button(NSLocalizedString("PERM_GRANT", bundle: .clawsy, comment: "")) {
                        permissionMonitor.requestPermission(perm)
                    }
                    .buttonStyle(.borderedProminent)
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
