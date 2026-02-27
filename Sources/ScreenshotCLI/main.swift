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

// ── Clawsy design tokens ─────────────────────────────────────────────────────

let clawsyRed   = Color(red: 0.85, green: 0.15, blue: 0.15)
let surface     = Color(red: 0.12, green: 0.12, blue: 0.14)
let surface2    = Color(red: 0.18, green: 0.18, blue: 0.20)
let textPrimary = Color.white
let textSub     = Color(white: 0.6)
let accent      = Color(red: 0.20, green: 0.60, blue: 1.00)

// ── Mock views ────────────────────────────────────────────────────────────────

// 1 – Main popover / menu
struct PopoverShot: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(clawsyRed)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CyberClaw").font(.headline).foregroundStyle(textPrimary)
                    Text("Online · SSH tunnel").font(.caption).foregroundStyle(Color.green)
                    Text("🧠 claude-sonnet-4-6").font(.caption2).foregroundStyle(textSub)
                }
                Spacer()
            }
            .padding(12)
            .background(surface2)

            Divider().background(Color.white.opacity(0.08))

            // Menu items
            ForEach([
                ("camera.fill",           "Screenshot",          "Vollbild / Bereich"),
                ("doc.on.clipboard.fill", "Zwischenablage",      "Jetzt senden"),
                ("bubble.left.fill",      "Quick Send",          "⌘⇧Space"),
                ("camera.viewfinder",     "Kamera",              ""),
            ], id: \.0) { icon, title, sub in
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(clawsyRed)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).foregroundStyle(textPrimary).font(.system(size: 13))
                        if !sub.isEmpty {
                            Text(sub).font(.caption2).foregroundStyle(textSub)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(textSub).font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.clear)
                Divider().background(Color.white.opacity(0.05))
            }

            HStack(spacing: 8) {
                ForEach([
                    ("gearshape", "Einstellungen"),
                    ("xmark.circle", "Trennen"),
                ], id: \.0) { icon, label in
                    Button { } label: {
                        Label(label, systemImage: icon).font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(textSub)
                }
                Spacer()
            }
            .padding(10)
            .background(surface2)
        }
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10)))
    }
}

// 2 – Settings
struct SettingsShot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Einstellungen").font(.title3.bold()).foregroundStyle(textPrimary).padding(16)
            Divider().background(Color.white.opacity(0.08))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        SettingsRow(icon: "network", label: "Server-Host", value: "agenthost")
                        SettingsRow(icon: "number",  label: "Port",        value: "18789")
                        SettingsRow(icon: "key.fill",label: "Token",       value: "••••••••••••")
                    }
                    Divider().background(Color.white.opacity(0.08))
                    Group {
                        SettingsRow(icon: "folder.fill",  label: "Geteilter Ordner",   value: "~/Documents/Clawsy")
                        SettingsToggle(icon: "wand.and.sparkles", label: "Erweiterter Kontext", on: true)
                        SettingsToggle(icon: "arrow.triangle.2.circlepath", label: "Auto-Update", on: true)
                    }
                }
                .padding(16)
            }
            Divider().background(Color.white.opacity(0.08))
            HStack {
                Spacer()
                Button("Speichern") {}
                    .buttonStyle(.borderedProminent)
                    .tint(clawsyRed)
            }.padding(12)
        }
        .background(surface)
    }
}
struct SettingsRow: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(clawsyRed).frame(width: 20)
            Text(label).foregroundStyle(textPrimary)
            Spacer()
            Text(value).foregroundStyle(textSub).font(.system(.body, design: .monospaced))
        }
    }
}
struct SettingsToggle: View {
    let icon: String; let label: String; let on: Bool
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(clawsyRed).frame(width: 20)
            Text(label).foregroundStyle(textPrimary)
            Spacer()
            Toggle("", isOn: .constant(on)).labelsHidden().tint(clawsyRed)
        }
    }
}

// 3 – Onboarding
struct OnboardingShot: View {
    var body: some View {
        VStack(spacing: 20) {
            // Logo placeholder
            ZStack {
                Circle().fill(clawsyRed.opacity(0.15)).frame(width: 72, height: 72)
                Image(systemName: "bolt.fill").font(.system(size: 34)).foregroundStyle(clawsyRed)
            }
            Text("Willkommen bei Clawsy").font(.title2.bold()).foregroundStyle(textPrimary)
            Text("Verbinde deinen KI-Agenten\nmit deinem Mac.")
                .multilineTextAlignment(.center).foregroundStyle(textSub)

            VStack(spacing: 10) {
                OnboardingStep(num: 1, text: "FinderSync aktivieren",   done: true)
                OnboardingStep(num: 2, text: "Server konfigurieren",    done: true)
                OnboardingStep(num: 3, text: "Erweiterungen erlauben",  done: false)
            }

            HStack(spacing: 12) {
                Button("Später") {}.buttonStyle(.bordered).foregroundStyle(textSub)
                Button("Weiter") {}.buttonStyle(.borderedProminent).tint(clawsyRed)
            }
        }
        .padding(32)
        .background(surface)
    }
}
struct OnboardingStep: View {
    let num: Int; let text: String; let done: Bool
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(done ? clawsyRed : surface2).frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(num)").font(.caption.bold()).foregroundStyle(textSub)
                }
            }
            Text(text).foregroundStyle(done ? textPrimary : textSub)
            Spacer()
        }
    }
}

// 4 – Mission Control
struct MissionControlShot: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "list.bullet.clipboard").foregroundStyle(clawsyRed)
                Text("Aufgaben-Übersicht").font(.headline).foregroundStyle(textPrimary)
                Spacer()
                Text("2 aktiv").font(.caption).foregroundStyle(textSub)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(surface2).clipShape(Capsule())
            }.padding(14)
            Divider().background(Color.white.opacity(0.08))

            VStack(spacing: 8) {
                TaskCard(title: "Clawsy Build läuft",  model: "anthropic/claude-sonnet-4-6", progress: 0.72, elapsed: "2m 14s")
                TaskCard(title: "Screenshot-Pipeline", model: "openai/gpt-4o",              progress: 0.35, elapsed: "45s")
            }.padding(12)
        }
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10)))
    }
}
struct TaskCard: View {
    let title: String; let model: String; let progress: Double; let elapsed: String
    var modelColor: Color {
        if model.hasPrefix("anthropic") { return .purple }
        if model.hasPrefix("openai")    { return .green }
        if model.hasPrefix("google")    { return .blue }
        return .orange
    }
    var modelShort: String { model.components(separatedBy: "/").last ?? model }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(textPrimary)
                Spacer()
                Text(modelShort).font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(modelColor.opacity(0.2))
                    .foregroundStyle(modelColor)
                    .clipShape(Capsule())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(surface2).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progress > 0.8 ? Color.green : accent)
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }.frame(height: 6)
            HStack {
                Text("\(Int(progress * 100))%").font(.caption2).foregroundStyle(textSub)
                Spacer()
                Text(elapsed).font(.caption2).foregroundStyle(textSub)
            }
        }
        .padding(12)
        .background(surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// 5 – File Sync dialog
struct FileSyncShot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "lock.shield.fill").foregroundStyle(clawsyRed).font(.title2)
                VStack(alignment: .leading) {
                    Text("Datei-Zugriff anfragen").font(.headline).foregroundStyle(textPrimary)
                    Text("Clawsy Agent möchte eine Datei schreiben").font(.caption).foregroundStyle(textSub)
                }
            }.padding(16)
            Divider().background(Color.white.opacity(0.08))
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Datei",      value: "Projektnotizen.md")
                InfoRow(label: "Vorgang",    value: "Schreiben")
                InfoRow(label: "Größe",      value: "4,2 KB")
                InfoRow(label: "Typ",        value: "Markdown-Dokument")
            }.padding(16)
            Divider().background(Color.white.opacity(0.08))
            HStack(spacing: 10) {
                Button { } label: { Label("Ablehnen", systemImage: "xmark").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button { } label: { Label("Erlauben", systemImage: "checkmark").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(clawsyRed)
            }.padding(12)
        }
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10)))
    }
}
struct InfoRow: View {
    let label: String; let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(textSub).frame(width: 70, alignment: .leading)
            Text(value).foregroundStyle(textPrimary).font(.system(.body, design: .monospaced))
        }.font(.system(size: 13))
    }
}

// 6 – Quick Send
struct QuickSendShot: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(clawsyRed)
                Text("Quick Send").font(.headline).foregroundStyle(textPrimary)
                Spacer()
                Text("⌘⇧Space").font(.caption2).foregroundStyle(textSub)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(surface2).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(surface2).frame(height: 80)
                Text("Fasse den Artikel zusammen…").foregroundStyle(textSub.opacity(0.6))
                    .font(.system(size: 13)).padding(10)
            }
            HStack {
                Toggle("", isOn: .constant(true)).labelsHidden().tint(clawsyRed).scaleEffect(0.8)
                Text("Kontext senden").font(.caption).foregroundStyle(textSub)
                Spacer()
                Button("Abbrechen") {}.buttonStyle(.bordered).foregroundStyle(textSub)
                Button("Senden") {}.buttonStyle(.borderedProminent).tint(clawsyRed)
            }
        }
        .padding(18)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10)))
    }
}

// ── Entry point ───────────────────────────────────────────────────────────────

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/screenshots"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

await MainActor.run {
    render(PopoverShot(),      width: 280, height: 340, to: "\(outDir)/01-popover.png")
    render(SettingsShot(),     width: 440, height: 360, to: "\(outDir)/02-settings.png")
    render(OnboardingShot(),   width: 480, height: 420, to: "\(outDir)/03-onboarding.png")
    render(MissionControlShot(),width: 340, height: 220,to: "\(outDir)/04-missioncontrol.png")
    render(FileSyncShot(),     width: 400, height: 300, to: "\(outDir)/05-filesync.png")
    render(QuickSendShot(),    width: 420, height: 200, to: "\(outDir)/06-quicksend.png")
}
