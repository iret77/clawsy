import SwiftUI

// MARK: - Clawsy Design System

/// Single source of truth for all visual tokens.
/// Every view uses these instead of hardcoded values.
/// Matches macOS Sonoma/Sequoia design language.
enum ClawsyTheme {

    // MARK: - Typography

    enum Font {
        /// Menu bar header: "Clawsy"
        static let headerTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        /// Host name next to header
        static let headerHostName = SwiftUI.Font.system(size: 11, weight: .medium)
        /// Status text under header
        static let headerStatus = SwiftUI.Font.system(size: 11)
        /// Menu item primary text
        static let menuItem = SwiftUI.Font.system(size: 13)
        /// Menu item secondary text (subtitle)
        static let menuItemSubtitle = SwiftUI.Font.system(size: 11)
        /// Keyboard shortcut labels
        static let shortcut = SwiftUI.Font.system(size: 11)
        /// Section headers in settings
        static let sectionHeader = SwiftUI.Font.system(size: 12, weight: .medium)
        /// Form labels in settings
        static let formLabel = SwiftUI.Font.system(size: 12)
        /// Form values / text fields
        static let formValue = SwiftUI.Font.system(size: 12)
        /// Small hints / footnotes
        static let caption = SwiftUI.Font.system(size: 10)
        /// Banner title
        static let bannerTitle = SwiftUI.Font.system(size: 12, weight: .semibold)
        /// Banner body
        static let bannerBody = SwiftUI.Font.system(size: 11)
        /// Monospaced code (commands, debug log)
        static let code = SwiftUI.Font.system(size: 11, design: .monospaced)
        /// Version footer
        static let footer = SwiftUI.Font.system(size: 10)
    }

    // MARK: - Spacing

    enum Spacing {
        /// Standard horizontal padding for content
        static let contentH: CGFloat = 16
        /// Standard vertical padding between sections
        static let sectionGap: CGFloat = 8
        /// Padding inside menu items
        static let menuItemH: CGFloat = 12
        static let menuItemV: CGFloat = 6
        /// Icon width for alignment
        static let iconWidth: CGFloat = 18
        /// Gap between icon and text
        static let iconTextGap: CGFloat = 10
        /// Header area padding
        static let headerTop: CGFloat = 14
        static let headerBottom: CGFloat = 12
        /// Popover width
        static let popoverWidth: CGFloat = 320
        /// Settings panel width
        static let settingsWidth: CGFloat = 380
        /// Corner radius for cards/banners
        static let cornerRadius: CGFloat = 8
        /// Corner radius for the popover
        static let popoverCornerRadius: CGFloat = 12
        /// Menu item corner radius (hover)
        static let menuItemCornerRadius: CGFloat = 4
    }

    // MARK: - Colors

    enum Colors {
        /// Status dot colors
        static let connected = Color(red: 0.2, green: 0.78, blue: 0.35)      // macOS green
        static let connecting = Color(red: 0.95, green: 0.6, blue: 0.1)       // macOS orange
        static let pairing = Color.blue
        static let disconnected = Color.gray.opacity(0.5)
        static let failed = Color(red: 0.9, green: 0.25, blue: 0.2)           // macOS red

        /// Menu item hover
        static let hoverBackground = Color.primary.opacity(0.08)

        /// Divider opacity (consistent everywhere)
        static let dividerOpacity: Double = 0.15

        /// Banner backgrounds
        static let errorBannerBackground = Color.red.opacity(0.08)
        static let infoBannerBackground = Color.blue.opacity(0.08)
        static let successBannerBackground = Color.green.opacity(0.08)
        static let pairingBannerGradient = LinearGradient(
            colors: [Color(red: 0.35, green: 0.2, blue: 0.9), Color(red: 0.5, green: 0.3, blue: 0.95)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// Shortcut key badge
        static let shortcutBadge = Color.secondary.opacity(0.12)

        /// Disabled content
        static let disabledContent = Color.secondary.opacity(0.4)
    }

    // MARK: - Animation

    enum Animation {
        /// State transitions (connect/disconnect, banner show/hide)
        static let stateChange = SwiftUI.Animation.easeInOut(duration: 0.25)
        /// Hover effects
        static let hover = SwiftUI.Animation.easeInOut(duration: 0.08)
        /// Banner slide
        static let bannerSlide = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.8)
        /// Status dot pulse
        static let pulse = SwiftUI.Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    }

    // MARK: - SF Symbols

    enum Icons {
        static let quickSend = "paperplane.fill"
        static let screenshot = "camera.viewfinder"
        static let clipboard = "doc.on.clipboard"
        static let camera = "camera.fill"
        static let connect = "bolt.fill"
        static let disconnect = "bolt.slash.fill"
        static let reconnect = "arrow.clockwise"
        static let settings = "gearshape.fill"
        static let taskOverview = "list.bullet.clipboard"
        static let quit = "xmark.circle"
        static let debug = "ladybug"
        static let update = "arrow.triangle.2.circlepath"
        static let folder = "folder"
        static let hotkey = "keyboard"
        static let tools = "wrench.and.screwdriver"
        static let connection = "globe"
        static let pairing = "link.badge.plus"
        static let warning = "exclamationmark.triangle.fill"
        static let success = "checkmark.circle.fill"
        static let retry = "arrow.clockwise"
        static let repair = "wrench.fill"
    }
}

// MARK: - Convenience View Modifiers

extension View {
    /// Apply standard menu item hover effect
    func menuItemStyle(isEnabled: Bool = true) -> some View {
        self
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Divider Extension

extension Divider {
    /// Standard Clawsy divider with consistent opacity
    func clawsy() -> some View {
        self.opacity(ClawsyTheme.Colors.dividerOpacity)
    }
}
