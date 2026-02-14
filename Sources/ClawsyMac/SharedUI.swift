import SwiftUI

// Helper for Visual Effect Blur (Native macOS look)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

struct MenuItemRow: View {
    var icon: String? = nil
    var title: String
    var subtitle: String? = nil
    var color: Color = .primary
    var isEnabled: Bool = true
    var shortcut: String? = nil
    var hasChevron: Bool = false
    var isMenu: Bool = false
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isEnabled ? color : color.opacity(0.3))
                    .frame(width: 18, alignment: .center)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title, bundle: .clawsy)
                    .font(.system(size: 13))
                    .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.5))
                
                if let subtitle = subtitle {
                    Text(subtitle, bundle: .clawsy)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            
            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(isHovering && isEnabled ? Color.primary.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hover in
            if isEnabled {
                withAnimation(.easeInOut(duration: 0.05)) {
                    isHovering = hover
                }
            }
        }
    }
}
