import SwiftUI
import ClawsyShared

struct RuleEditorView: View {
    let folderPath: String
    @Binding var isPresented: Bool

    @State private var manifest: ClawsyManifest
    @State private var editingRule: ClawsyRule? = nil
    @State private var showingAddRule = false

    init(folderPath: String, isPresented: Binding<Bool>) {
        self.folderPath = folderPath
        self._isPresented = isPresented
        let existing = ClawsyManifestManager.provision(for: folderPath)
        self._manifest = State(initialValue: existing)
    }

    var folderDisplayName: String {
        URL(fileURLWithPath: folderPath).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Regeln für Ordner")
                        .font(.system(size: 13, weight: .semibold))
                    Text(folderDisplayName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            if manifest.rules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Noch keine Regeln")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("Neue Regel hinzufügen, um Aktionen bei Datei-Ereignissen auszulösen.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(manifest.rules) { rule in
                            RuleRow(rule: rule, onEdit: {
                                editingRule = rule
                            }, onDelete: {
                                manifest.rules.removeAll { $0.id == rule.id }
                                save()
                            })
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            Divider().opacity(0.3)

            // Footer
            HStack {
                Button(action: {
                    let newRule = ClawsyRule()
                    editingRule = newRule
                }) {
                    Label("Regel hinzufügen", systemImage: "plus.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Text("\(manifest.rules.count) Regel\(manifest.rules.count == 1 ? "" : "n")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 380, height: 340)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .sheet(item: $editingRule) { rule in
            RuleEditSheet(rule: rule, isNew: !manifest.rules.contains(where: { $0.id == rule.id })) { saved in
                if let idx = manifest.rules.firstIndex(where: { $0.id == saved.id }) {
                    manifest.rules[idx] = saved
                } else {
                    manifest.rules.append(saved)
                }
                save()
            }
        }
    }

    private func save() {
        ClawsyManifestManager.write(manifest, to: folderPath)
    }
}

// MARK: - Rule Row

struct RuleRow: View {
    let rule: ClawsyRule
    let onEdit: () -> Void
    let onDelete: () -> Void

    var triggerIcon: String {
        switch rule.trigger {
        case "file_added": return "doc.badge.plus"
        case "file_changed": return "doc.badge.arrow.up"
        default: return "hand.tap"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: triggerIcon)
                .foregroundColor(.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(rule.filter).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text("→").foregroundColor(.secondary)
                    Text(rule.action).font(.system(size: 12)).foregroundColor(.secondary)
                }
                if !rule.prompt.isEmpty {
                    Text(rule.prompt)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: onDelete) {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.red.opacity(0.7))
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - Rule Edit Sheet

struct RuleEditSheet: View {
    @State var rule: ClawsyRule
    let isNew: Bool
    let onSave: (ClawsyRule) -> Void
    @Environment(\.dismiss) var dismiss

    let triggers = ["file_added", "file_changed", "manual"]
    let actions = ["send_to_agent", "notify"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Neue Regel" : "Regel bearbeiten")
                .font(.headline)
                .padding(.top, 4)

            Form {
                Picker("Auslöser", selection: $rule.trigger) {
                    Text("Datei hinzugefügt").tag("file_added")
                    Text("Datei geändert").tag("file_changed")
                    Text("Manuell").tag("manual")
                }

                TextField("Filter (z.B. *.pdf)", text: $rule.filter)
                    .font(.system(.body, design: .monospaced))

                Picker("Aktion", selection: $rule.action) {
                    Text("An Agent senden").tag("send_to_agent")
                    Text("Benachrichtigung").tag("notify")
                }

                if rule.action == "send_to_agent" {
                    TextField("Prompt-Präfix (optional)", text: $rule.prompt)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Speichern") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

extension ClawsyRule: Identifiable {}
