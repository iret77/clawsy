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
                    Text(l10n: "RULE_EDITOR_TITLE")
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
                    Text(l10n: "RULE_EDITOR_EMPTY")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text(l10n: "RULE_EDITOR_EMPTY_HINT")
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
                    Label {
                        Text(l10n: "RULE_ADD")
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Text(String(format: NSLocalizedString("RULE_COUNT %lld", bundle: .clawsy, comment: ""), manifest.rules.count))
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
            Text(isNew ? String(localized: "RULE_NEW", bundle: .clawsy) : String(localized: "RULE_EDIT", bundle: .clawsy))
                .font(.headline)
                .padding(.top, 4)

            Form {
                Picker(String(localized: "RULE_TRIGGER", bundle: .clawsy), selection: $rule.trigger) {
                    Text(l10n: "RULE_TRIGGER_FILE_ADDED").tag("file_added")
                    Text(l10n: "RULE_TRIGGER_FILE_CHANGED").tag("file_changed")
                    Text(l10n: "RULE_TRIGGER_MANUAL").tag("manual")
                }

                TextField(NSLocalizedString("RULE_FILTER_PLACEHOLDER", bundle: .clawsy, comment: ""), text: $rule.filter)
                    .font(.system(.body, design: .monospaced))

                Picker(String(localized: "RULE_ACTION", bundle: .clawsy), selection: $rule.action) {
                    Text(l10n: "RULE_ACTION_SEND_TO_AGENT").tag("send_to_agent")
                    Text(l10n: "RULE_ACTION_NOTIFY").tag("notify")
                }

                if rule.action == "send_to_agent" {
                    TextField(String(localized: "RULE_PROMPT_PREFIX", bundle: .clawsy), text: $rule.prompt)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(action: { dismiss() }) {
                    Text(l10n: "CANCEL")
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: {
                    onSave(rule)
                    dismiss()
                }) {
                    Text(l10n: "RULE_SAVE")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}


