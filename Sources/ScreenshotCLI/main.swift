import Foundation
import SwiftUI
import AppKit

// ── Render helper ─────────────────────────────────────────────────────────────

@MainActor
func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, to path: String) {
    let renderer = ImageRenderer(content:
        view
            .frame(width: width, height: height)
            .environment(\.colorScheme, .dark)
    )
    renderer.scale = 2.0
    guard let cgImage = renderer.cgImage else { print("❌ render failed: \(path)"); return }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else { print("❌ PNG encode failed: \(path)"); return }
    do { try data.write(to: URL(fileURLWithPath: path)); print("✅ \(path)") }
    catch { print("❌ write failed: \(path) — \(error)") }
}

// ── Clawsy window style ───────────────────────────────────────────────────────
// No traffic lights. Dark vibrancy panel, rounded corners, subtle border.

struct ClawsyPanel<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 12

    init(cornerRadius: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(white: 0.13, opacity: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(white: 1, opacity: 0.12), lineWidth: 0.5)
            )
    }
}

// ── Shared menu row ───────────────────────────────────────────────────────────

struct MenuRow: View {
    var icon: String? = nil
    var title: String
    var color: Color = Color(white: 0.85)
    var shortcut: String? = nil
    var hasChevron: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(isDisabled ? Color(white: 0.4) : color)
                    .frame(width: 18, alignment: .center)
            }
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(isDisabled ? Color(white: 0.35) : Color(white: 0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let sc = shortcut {
                Text(sc)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.4))
            }
            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.35))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// ── 1. Popover ────────────────────────────────────────────────────────────────

struct PopoverView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clawsy")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(white: 0.92))
                    Text("Online (Paired via SSH)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.5))
                }
                Spacer()
                Circle()
                    .fill(Color(red: 0.22, green: 0.85, blue: 0.45))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.green.opacity(0.6), radius: 3)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().background(Color(white: 1, opacity: 0.08))

            VStack(spacing: 1) {
                MenuRow(icon: "paperplane",        title: "Quick Send",  shortcut: "⌘⌥K")
                MenuRow(icon: "camera",            title: "Screenshot",  hasChevron: true, isDisabled: false)
                MenuRow(icon: "doc.on.clipboard",  title: "Clipboard",   shortcut: "⌘⌥V")
                MenuRow(icon: "video",             title: "Camera",      hasChevron: true)
            }
            .padding(.vertical, 4)

            Divider().background(Color(white: 1, opacity: 0.08))

            VStack(spacing: 1) {
                MenuRow(icon: "bolt.fill", title: "Connect", color: Color(red: 0.4, green: 0.7, blue: 1.0))
            }
            .padding(.vertical, 4)

            Divider().background(Color(white: 1, opacity: 0.08))

            VStack(spacing: 1) {
                MenuRow(icon: "list.bullet.clipboard", title: "Mission Control")
                MenuRow(icon: "info.circle",           title: "Last Metadata")
                MenuRow(icon: "gearshape",             title: "Settings...")
            }
            .padding(.vertical, 4)

            Divider().background(Color(white: 1, opacity: 0.08))

            VStack(spacing: 1) {
                MenuRow(icon: "xmark.circle", title: "Quit")
            }
            .padding(.vertical, 4)
        }
        .frame(width: 220)
    }
}

// ── 2. Settings ───────────────────────────────────────────────────────────────

struct SettingsRow: View {
    let label: String
    var value: String? = nil
    var isPassword: Bool = false
    var width: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(white: 1, opacity: 0.06))
            .overlay(
                Text(isPassword ? String(repeating: "•", count: 20) : (value ?? ""))
                    .font(.system(size: 12, design: value != nil ? .monospaced : .default))
                    .foregroundColor(isPassword ? Color(white: 0.4) : Color(white: 0.85))
                    .padding(.horizontal, 8),
                alignment: .leading
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(white: 1, opacity: 0.1), lineWidth: 0.5)
            )
            .frame(width: width, height: 28)
    }
}

struct Toggle2: View {
    let on: Bool
    var body: some View {
        Capsule()
            .fill(on ? Color(red: 0.2, green: 0.78, blue: 0.35) : Color(white: 0.25))
            .frame(width: 36, height: 20)
            .overlay(
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .offset(x: on ? 8 : -8),
                alignment: .center
            )
    }
}

struct SettingsSectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Close button row
            HStack {
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color(white: 0.35))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Divider().background(Color(white: 1, opacity: 0.08))

            VStack(alignment: .leading, spacing: 18) {

                // Gateway
                VStack(alignment: .leading, spacing: 8) {
                    SettingsSectionHeader(icon: "antenna.radiowaves.left.and.right", title: "Gateway", color: Color(red: 0.4, green: 0.65, blue: 1.0))
                    HStack(spacing: 6) {
                        SettingsRow(label: "host", value: "openclaw")
                        SettingsRow(label: "port", value: "18789", width: 72)
                    }
                    SettingsRow(label: "token", isPassword: true)
                }

                Divider().background(Color(white: 1, opacity: 0.07))

                // SSH Fallback
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SettingsSectionHeader(icon: "lock.shield", title: "SSH Fallback", color: Color(red: 1.0, green: 0.65, blue: 0.2))
                        Spacer()
                        Toggle2(on: true)
                    }
                    SettingsRow(label: "user", value: "username")
                    Text("Auto-tunnels via SSH if direct connection fails.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.4))
                }

                Divider().background(Color(white: 1, opacity: 0.07))

                // Extended Context
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SettingsSectionHeader(icon: "chart.bar.doc.horizontal", title: "Extended Context", color: Color(red: 0.3, green: 0.85, blue: 0.85))
                        Spacer()
                        Toggle2(on: true)
                    }
                    Text("Sends device info, active app, and battery level\nwith each message.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.4))
                }

                Divider().background(Color(white: 1, opacity: 0.07))

                // Hotkeys
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SettingsSectionHeader(icon: "keyboard", title: "Hotkeys", color: Color(red: 0.85, green: 0.5, blue: 0.9))
                        Spacer()
                        Text("Allow in Accessibility")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(red: 1.0, green: 0.75, blue: 0.0).opacity(0.25))
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.2))
                            .cornerRadius(4)
                    }
                    ForEach([
                        ("Quick Send",        "⌘ ⌥  K"),
                        ("Clipboard",         "⌘ ⌥  V"),
                        ("Camera",            "⌘ ⌥  P"),
                        ("Screenshot Full",   "⌘ ⌥  S"),
                        ("Screenshot Area",   "⌘ ⌥  A"),
                    ], id: \.0) { item in
                        HStack {
                            Text(item.0).font(.system(size: 12)).foregroundColor(Color(white: 0.75))
                            Spacer()
                            Text(item.1).font(.system(size: 11, design: .monospaced)).foregroundColor(Color(white: 0.45))
                        }
                    }
                }

                Divider().background(Color(white: 1, opacity: 0.07))

                // Updates
                VStack(alignment: .leading, spacing: 8) {
                    SettingsSectionHeader(icon: "arrow.clockwise.circle", title: "Updates", color: Color(red: 0.35, green: 0.75, blue: 0.5))
                    HStack {
                        Text("Current version: v0.5.3 #627")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.5))
                        Spacer()
                        Text("Check Now")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color(white: 1, opacity: 0.08))
                            .foregroundColor(Color(white: 0.8))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(white: 1, opacity: 0.12), lineWidth: 0.5))
                    }
                }

                Divider().background(Color(white: 1, opacity: 0.07))

                // Shared Folder
                VStack(alignment: .leading, spacing: 8) {
                    SettingsSectionHeader(icon: "folder.badge.plus", title: "Shared Folder", color: Color(red: 0.4, green: 0.82, blue: 0.45))
                    SettingsRow(label: "path", value: "~/Documents/Clawsy")
                    HStack(spacing: 8) {
                        Text("Select Folder")
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color(white: 1, opacity: 0.08))
                            .foregroundColor(Color(white: 0.75))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(white: 1, opacity: 0.1), lineWidth: 0.5))
                        Text("Show in Finder")
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color(white: 1, opacity: 0.08))
                            .foregroundColor(Color(white: 0.75))
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(white: 1, opacity: 0.1), lineWidth: 0.5))
                    }
                    Text("Data stays local.")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.3))
                }
            }
            .padding(16)
        }
        .frame(width: 280)
    }
}

// ── 3. Hero — Mac Desktop Context ─────────────────────────────────────────────
// macOS-style desktop: gradient wallpaper + menu bar + popover + settings open

struct HeroView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {

            // Wallpaper — macOS Sonoma-style blue/purple gradient
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.08, green: 0.08, blue: 0.35), location: 0),
                    .init(color: Color(red: 0.12, green: 0.15, blue: 0.55), location: 0.35),
                    .init(color: Color(red: 0.25, green: 0.30, blue: 0.70), location: 0.65),
                    .init(color: Color(red: 0.15, green: 0.20, blue: 0.50), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle wave highlight
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 1, opacity: 0.06), Color.clear],
                        center: .center, startRadius: 0, endRadius: 400
                    )
                )
                .frame(width: 700, height: 300)
                .offset(x: 200, y: 300)

            VStack(spacing: 0) {

                // Menu bar
                HStack(spacing: 0) {
                    // Left side — Apple + app menus (simplified)
                    HStack(spacing: 16) {
                        Image(systemName: "applelogo")
                            .font(.system(size: 13, weight: .medium))
                        Text("Finder").font(.system(size: 13, weight: .semibold))
                        ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { item in
                            Text(item).font(.system(size: 13))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.leading, 16)

                    Spacer()

                    // Right side — status icons + Clawsy
                    HStack(spacing: 12) {
                        ForEach(["wifi", "battery.100", "clock"], id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 13))
                        }
                        Text("Sat 28 Feb  22:03")
                            .font(.system(size: 12))

                        // Clawsy icon in menu bar — highlighted
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(white: 1, opacity: 0.15))
                                .frame(width: 26, height: 20)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .foregroundColor(Color(white: 0.85))
                    .padding(.trailing, 12)
                }
                .frame(height: 28)
                .background(Color(white: 0, opacity: 0.35))

                Spacer()
            }

            // Popover — drops down from the Clawsy menu bar icon
            ClawsyPanel(cornerRadius: 10) {
                PopoverView()
            }
            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 8)
            .offset(x: 520, y: 30)

            // Settings panel — open to the right of the popover
            ClawsyPanel(cornerRadius: 12) {
                SettingsView()
            }
            .shadow(color: Color.black.opacity(0.5), radius: 24, x: 0, y: 8)
            .offset(x: 755, y: 30)
        }
        .frame(width: 1100, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
}

// ── 4. Onboarding ─────────────────────────────────────────────────────────────

struct OnboardingStep: View {
    let icon: String
    let title: String
    let subtitle: String
    let done: Bool
    let critical: Bool
    let action: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : (critical ? "exclamationmark.triangle.fill" : "circle.dashed"))
                .font(.system(size: 19))
                .foregroundColor(done ? Color(red: 0.22, green: 0.85, blue: 0.45) : (critical ? Color(red: 1.0, green: 0.7, blue: 0.15) : Color(white: 0.35)))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(Color(white: 0.9))
                    if !critical {
                        Text("optional").font(.system(size: 10)).foregroundColor(Color(white: 0.4))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color(white: 1, opacity: 0.07)).cornerRadius(3)
                    }
                }
                Text(subtitle).font(.system(size: 11)).foregroundColor(Color(white: 0.45)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let action = action, !done {
                Text(action).font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(white: 1, opacity: 0.08))
                    .foregroundColor(Color(white: 0.75))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(white: 1, opacity: 0.1), lineWidth: 0.5))
            }
        }
    }
}

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.4, green: 0.65, blue: 1.0).opacity(0.18))
                        .frame(width: 58, height: 58)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(Color(red: 0.5, green: 0.75, blue: 1.0))
                }
                Text("Welcome to Clawsy")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(white: 0.92))
                Text("Connect your AI agent to your Mac.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.45))
            }
            .padding(.top, 24).padding(.bottom, 18)

            Divider().background(Color(white: 1, opacity: 0.08))

            VStack(spacing: 14) {
                OnboardingStep(icon: "folder.fill",         title: "App Location",          subtitle: "Move Clawsy to your Applications folder.", done: true,  critical: true,  action: nil)
                OnboardingStep(icon: "hand.raised.fill",    title: "Accessibility",          subtitle: "Required for global keyboard shortcuts.",  done: true,  critical: true,  action: nil)
                OnboardingStep(icon: "folder.badge.gearshape", title: "FinderSync Extension", subtitle: "Enables right-click actions in Finder.",  done: false, critical: false, action: "Enable")
            }
            .padding(.horizontal, 22).padding(.vertical, 18)

            Spacer()

            Divider().background(Color(white: 1, opacity: 0.08))

            HStack {
                Text("Skip").font(.system(size: 13))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color(white: 1, opacity: 0.07))
                    .foregroundColor(Color(white: 0.6))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 1, opacity: 0.1), lineWidth: 0.5))
                Spacer()
                Text("Done").font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color(red: 0.4, green: 0.65, blue: 1.0))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 380, height: 360)
    }
}

// ── 5. Mission Control ────────────────────────────────────────────────────────

struct TaskCard: View {
    let title: String
    let model: String
    let progress: Double
    let status: String
    let elapsed: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(Color(white: 0.88))
                Spacer()
                Text(model).font(.system(size: 10))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(red: 0.55, green: 0.45, blue: 0.85).opacity(0.25))
                    .foregroundColor(Color(red: 0.7, green: 0.6, blue: 1.0))
                    .clipShape(Capsule())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 1, opacity: 0.07)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.4, green: 0.65, blue: 1.0))
                        .frame(width: geo.size.width * progress, height: 5)
                }
            }.frame(height: 5)
            HStack {
                Text(status).font(.system(size: 11)).foregroundColor(Color(white: 0.38)).lineLimit(1)
                Spacer()
                Text(elapsed).font(.system(size: 11)).foregroundColor(Color(white: 0.35))
            }
        }
        .padding(12)
        .background(Color(white: 1, opacity: 0.05))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 1, opacity: 0.07), lineWidth: 0.5))
    }
}

struct MissionControlView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mission Control").font(.system(size: 14, weight: .semibold)).foregroundColor(Color(white: 0.88))
                Spacer()
                Text("2 active").font(.system(size: 11))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(red: 0.4, green: 0.65, blue: 1.0).opacity(0.2))
                    .foregroundColor(Color(red: 0.5, green: 0.75, blue: 1.0))
                    .clipShape(Capsule())
            }
            .padding(14)

            Divider().background(Color(white: 1, opacity: 0.08))

            VStack(spacing: 8) {
                TaskCard(title: "Building Clawsy v0.5.4",   model: "claude-sonnet-4-6", progress: 0.72, status: "Compiling Swift sources…",    elapsed: "2m 14s")
                TaskCard(title: "Updating README",           model: "claude-sonnet-4-6", progress: 0.38, status: "Writing features section…",   elapsed: "45s")
            }
            .padding(12)
        }
        .frame(width: 320)
    }
}

// ── 6. File Sync ──────────────────────────────────────────────────────────────

struct FileSyncView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill").font(.system(size: 20)).foregroundColor(Color(red: 0.4, green: 0.65, blue: 1.0))
                VStack(alignment: .leading, spacing: 1) {
                    Text("File Sync Request").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(white: 0.9))
                    Text("The agent wants to write a file.").font(.system(size: 11)).foregroundColor(Color(white: 0.45))
                }
            }
            .padding(14)

            Divider().background(Color(white: 1, opacity: 0.08))

            VStack(alignment: .leading, spacing: 8) {
                ForEach([("File", "ProjectNotes.md"), ("Operation", "Write"), ("Size", "4.2 KB"), ("Location", "~/Documents/Clawsy")], id: \.0) { row in
                    HStack {
                        Text(row.0).font(.system(size: 12)).foregroundColor(Color(white: 0.4)).frame(width: 68, alignment: .leading)
                        Text(row.1).font(.system(size: 12, design: .monospaced)).foregroundColor(Color(white: 0.82))
                    }
                }
            }
            .padding(14)

            Divider().background(Color(white: 1, opacity: 0.08))

            HStack(spacing: 8) {
                Text("Deny")
                    .font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(Color(white: 1, opacity: 0.07))
                    .foregroundColor(Color(white: 0.6))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 1, opacity: 0.1), lineWidth: 0.5))
                Text("Just this once")
                    .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(Color(red: 0.4, green: 0.65, blue: 1.0))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .padding(12)
        }
        .frame(width: 320)
    }
}

// ── 7. Quick Send ─────────────────────────────────────────────────────────────

struct QuickSendView: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 18))
                .foregroundColor(Color(red: 0.4, green: 0.65, blue: 1.0).opacity(0.7))
            Text("Send something to OpenClaw...")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(Color(white: 0.3))
            Spacer()
            HStack(spacing: 10) {
                Text("↵ Send").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.25))
                Text("esc Cancel").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.25))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 500)
    }
}

// ── Entry point ───────────────────────────────────────────────────────────────

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/screenshots"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

await MainActor.run {
    // Hero — Mac desktop context (wide, landscape)
    render(HeroView(), width: 1100, height: 560, to: "\(outDir)/00-hero.png")

    // Individual panels — wrapped in ClawsyPanel for realistic frames
    render(
        ClawsyPanel(cornerRadius: 10) { PopoverView() }
            .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 6)
            .padding(20)
            .background(Color(white: 0.08)),
        width: 260, height: 360, to: "\(outDir)/01-popover.png"
    )
    render(
        ClawsyPanel(cornerRadius: 12) { SettingsView() }
            .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 8)
            .padding(20)
            .background(Color(white: 0.08)),
        width: 320, height: 780, to: "\(outDir)/02-settings.png"
    )
    render(
        ClawsyPanel(cornerRadius: 12) { OnboardingView() }
            .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 8)
            .padding(20)
            .background(Color(white: 0.08)),
        width: 420, height: 400, to: "\(outDir)/03-onboarding.png"
    )
    render(
        ClawsyPanel(cornerRadius: 10) { MissionControlView() }
            .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 6)
            .padding(20)
            .background(Color(white: 0.08)),
        width: 360, height: 280, to: "\(outDir)/04-missioncontrol.png"
    )
    render(
        ClawsyPanel(cornerRadius: 10) { FileSyncView() }
            .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 6)
            .padding(20)
            .background(Color(white: 0.08)),
        width: 360, height: 260, to: "\(outDir)/05-filesync.png"
    )
    render(
        ClawsyPanel(cornerRadius: 16) { QuickSendView() }
            .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 8)
            .padding(20)
            .background(Color(white: 0.08)),
        width: 540, height: 110, to: "\(outDir)/06-quicksend.png"
    )
}
