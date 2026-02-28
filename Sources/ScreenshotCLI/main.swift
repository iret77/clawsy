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
    guard let cgImage = renderer.cgImage else {
        print("❌ render failed: \(path)")
        return
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("❌ PNG encode failed: \(path)")
        return
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        print("✅ \(path)")
    } catch {
        print("❌ write failed: \(path) — \(error)")
    }
}

// ── Shared style helpers ──────────────────────────────────────────────────────

// Mirrors the real app: uses system semantic colors (dark mode forced by renderer)
let accentBlue = Color.accentColor

// MenuItemRow — mirrors SharedUI.swift
struct MockMenuItemRow: View {
    var icon: String? = nil
    var title: String
    var color: Color = .primary
    var isEnabled: Bool = true
    var shortcut: String? = nil
    var hasChevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isEnabled ? color : color.opacity(0.3))
                    .frame(width: 18, alignment: .center)
            }
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

// ── 1. Main Popover ───────────────────────────────────────────────────────────
// Mirrors: ContentView (the menu bar popover), width 240

struct PopoverShot: View {
    var body: some View {
        VStack(spacing: 0) {

            // Header — mirrors the HStack at top of ContentView
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clawsy")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Online (Paired via SSH)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: "brain")
                            .font(.system(size: 9))
                        Text("claude-sonnet-4-6")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                }
                Spacer()
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.green.opacity(0.5), radius: 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().opacity(0.5)

            // Menu items — in exact order from ContentView
            VStack(spacing: 2) {
                MockMenuItemRow(icon: "paperplane.fill", title: "Quick Send",
                                isEnabled: true, shortcut: "⌘⇧K")
                MockMenuItemRow(icon: "camera",         title: "Screenshot",
                                isEnabled: true, hasChevron: true)
                MockMenuItemRow(icon: "doc.on.clipboard", title: "Clipboard",
                                isEnabled: true, shortcut: "⌘⇧V")
                MockMenuItemRow(icon: "video.fill",     title: "Camera",
                                isEnabled: true, hasChevron: true)

                Divider().padding(.vertical, 4).opacity(0.5)

                MockMenuItemRow(icon: "power", title: "Disconnect", color: .red, isEnabled: true)

                Divider().padding(.vertical, 4).opacity(0.5)

                MockMenuItemRow(icon: "list.bullet.clipboard", title: "Mission Control", isEnabled: true)
                MockMenuItemRow(icon: "info.bubble.fill",      title: "Last Metadata",   isEnabled: true)
                MockMenuItemRow(icon: "gearshape.fill",        title: "Settings...",     isEnabled: true)

                Divider().padding(.vertical, 4).opacity(0.5)

                MockMenuItemRow(icon: "xmark.circle.fill", title: "Quit", isEnabled: true)
            }
            .padding(6)
        }
        .frame(width: 240)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// ── 2. Settings Popover ───────────────────────────────────────────────────────
// Mirrors: SettingsView, width 380

struct SettingsShot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 24) {
                let _ = "" // no ScrollView — ImageRenderer doesn't render offscreen content

                    // Gateway
                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text("Gateway")
                                .font(.system(size: 13, weight: .semibold))
                        } icon: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        .foregroundColor(.blue)

                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.1))
                                .overlay(
                                    Text("agenthost")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 8),
                                    alignment: .leading
                                )
                                .frame(height: 28)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.1))
                                .overlay(
                                    Text("18789")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 8),
                                    alignment: .leading
                                )
                                .frame(width: 80, height: 28)
                        }
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.1))
                            .overlay(
                                Text("••••••••••••••••")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8),
                                alignment: .leading
                            )
                            .frame(height: 28)
                    }

                    Divider().opacity(0.3)

                    // SSH Fallback
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label {
                                Text("SSH Fallback")
                                    .font(.system(size: 13, weight: .semibold))
                            } icon: {
                                Image(systemName: "lock.shield")
                            }
                            .foregroundColor(.orange)
                            Spacer()
                            Toggle("", isOn: .constant(true))
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                        }
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.1))
                            .overlay(
                                Text("claw")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 8),
                                alignment: .leading
                            )
                            .frame(height: 28)
                        Text("Auto-tunnels port 18789 if direct connection fails.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Divider().opacity(0.3)

                    // Extended Context
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label {
                                Text("Extended Context")
                                    .font(.system(size: 13, weight: .semibold))
                            } icon: {
                                Image(systemName: "chart.bar.doc.horizontal")
                            }
                            .foregroundColor(.cyan)
                            Spacer()
                            Toggle("", isOn: .constant(false))
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                        }
                        Text("Sends device info, active app, and battery level with each message.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Divider().opacity(0.3)

                    // Shared Folder
                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text("Shared Folder")
                                .font(.system(size: 13, weight: .semibold))
                        } icon: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .foregroundColor(.green)

                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.05))
                            .overlay(
                                Text("~/Documents/Clawsy")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 12),
                                alignment: .leading
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                            .frame(height: 32)

                        HStack(spacing: 8) {
                            Label("Select Folder", systemImage: "folder.fill.badge.plus")
                                .font(.system(size: 12))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                            Label("Show in Finder", systemImage: "magnifyingglass")
                                .font(.system(size: 12))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .foregroundColor(.primary)
                    }
                }
                .padding(20)

            Divider().opacity(0.3)

            // Footer
            HStack(spacing: 4) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .foregroundColor(.secondary)
                Image(systemName: "checklist")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Vibrant. Secure.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.03))
        }
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// ── 3. Onboarding ─────────────────────────────────────────────────────────────
// Mirrors: OnboardingView, 420×460

struct OnboardingShot: View {
    var body: some View {
        VStack(spacing: 0) {

            // Header
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.accentColor)
                }
                Text("Welcome to Clawsy")
                    .font(.system(size: 18, weight: .bold))
                Text("Connect your AI agent to your Mac.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider().opacity(0.3)

            // Checklist — mirrors OnboardingView steps
            VStack(spacing: 16) {
                MockOnboardingStep(
                    icon: "folder.fill",
                    title: "App Location",
                    subtitle: "Move Clawsy to your Applications folder.",
                    isCompleted: true,
                    isCritical: true,
                    actionLabel: "Move to Applications"
                )
                MockOnboardingStep(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    subtitle: "Required for global keyboard shortcuts.",
                    isCompleted: true,
                    isCritical: true,
                    actionLabel: "Open Settings"
                )
                MockOnboardingStep(
                    icon: "folder.badge.gearshape",
                    title: "FinderSync Extension",
                    subtitle: "Enables right-click actions in Finder.",
                    isCompleted: false,
                    isCritical: false,
                    actionLabel: "Enable"
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Spacer()

            Divider().opacity(0.3)

            // Footer buttons
            HStack {
                Text("Skip")
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(6)
                    .foregroundColor(.primary)
                Spacer()
                Text("Done")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .cornerRadius(6)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 420, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct MockOnboardingStep: View {
    let icon: String
    let title: String
    let subtitle: String
    let isCompleted: Bool
    let isCritical: Bool
    let actionLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCompleted
                  ? "checkmark.circle.fill"
                  : (isCritical ? "exclamationmark.triangle.fill" : "circle.dashed"))
                .font(.system(size: 20))
                .foregroundColor(isCompleted ? .green : (isCritical ? .orange : .secondary))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if !isCritical {
                        Text("optional")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !isCompleted {
                Text(actionLabel)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(5)
                    .foregroundColor(.primary)
            }
        }
    }
}

// ── 4. Mission Control ────────────────────────────────────────────────────────
// Mirrors: MissionControlView popover

struct MissionControlShot: View {
    var body: some View {
        VStack(spacing: 12) {

            // Header
            HStack {
                Text("Tasks (2 active)")
                    .font(.headline)
                Spacer()
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.accentColor)
            }

            // Task cards — mirrors TaskRowView
            VStack(spacing: 8) {
                MockTaskRow(
                    title: "Building Clawsy v0.5.0",
                    model: "claude-sonnet-4-6",
                    modelProvider: "anthropic",
                    progress: 0.72,
                    statusText: "Compiling Swift sources…",
                    elapsed: "2m 14s"
                )
                MockTaskRow(
                    title: "Updating README",
                    model: "claude-sonnet-4-6",
                    modelProvider: "anthropic",
                    progress: 0.35,
                    statusText: "Writing feature section…",
                    elapsed: "45s"
                )
            }
        }
        .padding()
        .frame(width: 340)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct MockTaskRow: View {
    let title: String
    let model: String
    let modelProvider: String
    let progress: Double
    let statusText: String
    let elapsed: String

    var modelColor: Color {
        switch modelProvider {
        case "anthropic": return Color(red: 0.55, green: 0.45, blue: 0.85)
        case "openai":    return Color(red: 0.2, green: 0.75, blue: 0.5)
        case "google":    return Color(red: 0.35, green: 0.6, blue: 0.95)
        default:          return Color(red: 0.9, green: 0.6, blue: 0.2)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(model)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(modelColor.opacity(0.2))
                    .foregroundColor(modelColor)
                    .clipShape(Capsule())
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progress > 0.8 ? Color(red: 0.2, green: 0.78, blue: 0.35) : Color(red: 0.4, green: 0.6, blue: 1.0))
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(elapsed)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// ── 5. File Sync Request ──────────────────────────────────────────────────────
// Mirrors: FileSyncRequestWindow

struct FileSyncShot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text("File Sync Request")
                        .font(.headline)
                    Text("The agent wants to write a file.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)

            Divider().opacity(0.3)

            // Details
            VStack(alignment: .leading, spacing: 10) {
                MockInfoRow(label: "File",      value: "ProjectNotes.md")
                MockInfoRow(label: "Operation", value: "Write")
                MockInfoRow(label: "Size",      value: "4.2 KB")
                MockInfoRow(label: "Location",  value: "~/Documents/Clawsy")
            }
            .padding(16)

            Divider().opacity(0.3)

            // Actions — mirrors ALLOW_ONCE / ALLOW_1H / DENY
            HStack(spacing: 8) {
                Text("Deny")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(6)
                    .foregroundColor(.primary)

                Text("Just this once")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .cornerRadius(6)
                    .foregroundColor(.white)
            }
            .padding(12)
        }
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct MockInfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
        }
        .font(.system(size: 13))
    }
}

// ── 6. Quick Send ─────────────────────────────────────────────────────────────
// Mirrors: QuickSendView (floating panel, borderless)

struct QuickSendShot: View {
    var body: some View {
        VStack(spacing: 0) {

            // Input area
            HStack(spacing: 12) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor.opacity(0.8))

                Text("Send something to OpenClaw...")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.secondary.opacity(0.5))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            Divider().opacity(0.3)

            // Footer hints — mirrors QuickSendView footer
            HStack {
                Spacer()
                HStack(spacing: 16) {
                    Label("Send", systemImage: "return")
                    Label("Cancel", systemImage: "escape")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.05))
        }
        .frame(width: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// ── Entry point ───────────────────────────────────────────────────────────────

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/screenshots"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

await MainActor.run {
    render(PopoverShot(),        width: 240, height: 380, to: "\(outDir)/01-popover.png")
    render(SettingsShot(),       width: 380, height: 680, to: "\(outDir)/02-settings.png")
    render(OnboardingShot(),     width: 420, height: 460, to: "\(outDir)/03-onboarding.png")
    render(MissionControlShot(), width: 340, height: 240, to: "\(outDir)/04-missioncontrol.png")
    render(FileSyncShot(),       width: 380, height: 240, to: "\(outDir)/05-filesync.png")
    render(QuickSendShot(),      width: 500, height: 100, to: "\(outDir)/06-quicksend.png")
}
