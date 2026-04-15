import SwiftUI

// MARK: - Visual Effect (Native macOS Vibrancy)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

// MARK: - Menu Item Row

struct MenuItemRow: View {
    var icon: String? = nil
    var title: String
    var subtitle: String? = nil
    var color: Color = .primary
    var isEnabled: Bool = true
    var shortcut: String? = nil
    var hasChevron: Bool = false

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: ClawsyTheme.Spacing.iconTextGap) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(isEnabled ? color : ClawsyTheme.Colors.disabledContent)
                    .frame(width: ClawsyTheme.Spacing.iconWidth, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title), bundle: .clawsy)
                    .font(ClawsyTheme.Font.menuItem)
                    .foregroundColor(isEnabled ? .primary : ClawsyTheme.Colors.disabledContent)

                if let subtitle = subtitle {
                    Text(LocalizedStringKey(subtitle), bundle: .clawsy)
                        .font(ClawsyTheme.Font.menuItemSubtitle)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let shortcut = shortcut {
                Text(shortcut)
                    .font(ClawsyTheme.Font.shortcut)
                    .foregroundColor(.secondary.opacity(0.5))
            }

            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, ClawsyTheme.Spacing.menuItemH)
        .padding(.vertical, ClawsyTheme.Spacing.menuItemV)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: ClawsyTheme.Spacing.menuItemCornerRadius)
                .fill(isHovering && isEnabled ? ClawsyTheme.Colors.hoverBackground : Color.clear)
        )
        .onHover { hover in
            if isEnabled {
                withAnimation(ClawsyTheme.Animation.hover) {
                    isHovering = hover
                }
            }
        }
    }
}

// MARK: - Status HUD

struct StatusHUDView: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(.white)

            Text(LocalizedStringKey(title), bundle: .clawsy)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(24)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .overlay(Color.black.opacity(0.4))
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
