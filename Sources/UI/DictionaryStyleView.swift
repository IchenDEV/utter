import SwiftUI

struct DictionaryStyleView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var dictionary = PersonalDictionary.shared
    @State private var newRule = ""

    var body: some View {
        Form {
            if !settings.useCustomSystemPrompt {
                styleSection
            }
            IndustryLexiconView()
            DictionaryManagementView()
            editRulesSection
            customSystemPromptSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .settingsPageSurface()
    }

    private var styleSection: some View {
        Section {
            Picker(L("style.title"), selection: $settings.languageStyle) {
                ForEach(LanguageStyle.allCases, id: \.self) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: settings.languageStyle) { _, style in
                guard style.usesCustomPrompt,
                      settings.customStylePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || LanguageStyle.looksLikePresetPrompt(settings.customStylePrompt) else { return }
                settings.customStylePrompt = style.defaultPrompt
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("style.prompt"))
                    .font(.subheadline.weight(.medium))

                if settings.languageStyle.usesCustomPrompt {
                    TextEditor(text: $settings.customStylePrompt)
                        .font(.system(.caption, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 88)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(settings.languageStyle.defaultPrompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text(L("style.title"))
        } footer: {
            Text(settings.languageStyle.usesCustomPrompt
                 ? L("style.prompt_help")
                 : L("style.preset_help"))
        }
    }

    private var editRulesSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(L("rules.placeholder"), text: $newRule)
                    .textFieldStyle(.roundedBorder)
                Button(L("common.add")) {
                    guard !newRule.isEmpty else { return }
                    dictionary.addRule(description: newRule)
                    newRule = ""
                }
                .controlSize(.small)
            }

            if dictionary.editRules.isEmpty {
                emptyHint(L("rules.empty"))
            } else {
                ForEach(Array(dictionary.editRules.enumerated()), id: \.element.id) { index, rule in
                    HStack {
                        Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(rule.enabled ? .green : .secondary)
                            .font(.caption)
                        Text(rule.description)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        deleteButton { dictionary.removeRule(at: IndexSet(integer: index)) }
                    }
                }
            }
        } header: {
            Text(L("rules.title"))
        } footer: {
            Text(L("rules.subtitle"))
        }
    }

    private var customSystemPromptSection: some View {
        Section {
            Toggle(isOn: $settings.useCustomSystemPrompt) {
                Text(L("custom_prompt.desc"))
            }

            if settings.useCustomSystemPrompt {
                TextEditor(text: $settings.customSystemPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 130, maxHeight: 260)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        } header: {
            Text(L("custom_prompt.title"))
        } footer: {
            if settings.useCustomSystemPrompt {
                Text(L("custom_prompt.hint"))
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 28)
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.caption2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(L("common.delete"))
    }
}
