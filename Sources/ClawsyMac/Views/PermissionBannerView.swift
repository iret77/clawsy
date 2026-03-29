import SwiftUI

/// Permission banner for the main menu popover.
/// Shows only when required permissions are missing. Compact, non-alarming design.
struct PermissionBannerView: View {
    @ObservedObject var permissionMonitor: PermissionMonitor

    var body: some View {
        let missing = permissionMonitor.missingRequired

        VStack(alignment: .leading, spacing: 4) {
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
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(ClawsyTheme.Spacing.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: ClawsyTheme.Spacing.cornerRadius)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 0.5)
        )
    }
}

/// A single permission row — compact variant for the popover banner.
private struct PermissionBannerRow: View {
    let permission: ClawsyPermission
    let isGranted: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Status icon — green checkmark when granted, gray circle when not
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.1))
                    .frame(width: 26, height: 26)
                Image(systemName: isGranted ? "checkmark" : permission.icon)
                    .font(.system(size: 11, weight: isGranted ? .bold : .regular))
                    .foregroundColor(isGranted ? .green : .accentColor)
            }

            // Title + subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(permission.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                Text(permission.description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if !isGranted {
                Button(action: onGrant) {
                    HStack(spacing: 3) {
                        Image(systemName: permission.hasNativeGrant ? "checkmark.circle" : "gear")
                            .font(.system(size: 10))
                        Text(permission.hasNativeGrant ? "OK" : "Open")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 3)
    }
}
