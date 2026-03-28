import SwiftUI

/// Permission banner for the main menu popover.
/// Follows OpenClaw's PermissionRow design: circular icon background,
/// clear explanatory subtitle, unified "Grant" button, green checkmark when granted.
struct PermissionBannerView: View {
    @ObservedObject var permissionMonitor: PermissionMonitor

    var body: some View {
        let missing = permissionMonitor.missingRequired

        VStack(alignment: .leading, spacing: 6) {
            // Intro text — tells first-time users what this is and why
            Text(NSLocalizedString("PERM_BANNER_INTRO", bundle: .clawsy, comment: ""))
                .font(ClawsyTheme.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

            ForEach(missing) { perm in
                PermissionBannerRow(
                    permission: perm,
                    isGranted: permissionMonitor.status[perm] == true,
                    onGrant: { permissionMonitor.requestPermission(perm) }
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(ClawsyTheme.Spacing.cornerRadius)
    }
}

/// A single permission row — modeled after OpenClaw's PermissionRow (compact variant).
/// Circular icon, title + subtitle, and status/action on the right.
private struct PermissionBannerRow: View {
    let permission: ClawsyPermission
    let isGranted: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Circular icon background — green when granted, orange when missing
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.2) : Color.orange.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: permission.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isGranted ? .green : .orange)
            }

            // Title + description — never truncated
            VStack(alignment: .leading, spacing: 1) {
                Text(permission.displayName)
                    .font(ClawsyTheme.Font.bannerTitle)
                    .foregroundColor(.primary)
                Text(permission.description)
                    .font(ClawsyTheme.Font.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            // Right side: checkmark when granted, "Grant" button when not
            if isGranted {
                Label {
                    Text(NSLocalizedString("PERM_GRANTED", bundle: .clawsy, comment: ""))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .labelStyle(.iconOnly)
                .foregroundColor(.green)
                .font(.title3)
                .help(NSLocalizedString("PERM_GRANTED", bundle: .clawsy, comment: ""))
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Button(NSLocalizedString("PERM_GRANT", bundle: .clawsy, comment: "")) {
                        onGrant()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minWidth: 68, alignment: .trailing)

                    Text(NSLocalizedString("PERM_REQUEST_ACCESS", bundle: .clawsy, comment: ""))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 86, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }
}
