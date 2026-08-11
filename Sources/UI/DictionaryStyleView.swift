import SwiftUI

struct DictionaryStyleView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var dictionary = PersonalDictionary.shared

    @State private var newRule = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DictionaryManagementView()
                Divider()
                customSystemPromptSection
                if !settings.useCustomSystemPrompt {
                    Divider()
                    styleSection
                }
                Divider()
                editRulesSection
            }
            .padding(20)
        }
    }

    // MARK: - Custom System Prompt

    private var customSystemPromptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("custom_prompt.title"), systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $settings.useCustomSystemPrompt)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            Text(L("custom_prompt.desc"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.useCustomSystemPrompt {
                TextEditor(text: $settings.customSystemPrompt)
                    .font(.system(size: 11.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 140, maxHeight: 280)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )

                Text(L("custom_prompt.hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Style

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("style.title"), systemImage: "paintbrush")
                .font(.headline)

            HStack(spacing: 10) {
                ForEach(LanguageStyle.allCases, id: \.self) { style in
                    StylePresetCard(
                        style: style,
                        isSelected: settings.languageStyle == style
                    ) {
                        settings.languageStyle = style
                        if style.usesCustomPrompt,
                           settings.customStylePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || LanguageStyle.looksLikePresetPrompt(settings.customStylePrompt) {
                            settings.customStylePrompt = style.defaultPrompt
                        }
                    }
                }
            }

            if settings.languageStyle.usesCustomPrompt {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("style.prompt"))
                        .font(.subheadline.weight(.medium))
                    TextEditor(text: $settings.customStylePrompt)
                        .font(.system(size: 11.5, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 92)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                    Text(L("style.prompt_help"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("style.prompt"))
                        .font(.subheadline.weight(.medium))
                    Text(settings.languageStyle.defaultPrompt)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                    Text(L("style.preset_help"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Edit Rules

    private var editRulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("rules.title"), systemImage: "list.bullet.rectangle")
                .font(.headline)
            Text(L("rules.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)

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
                VStack(spacing: 0) {
                    ForEach(Array(dictionary.editRules.enumerated()), id: \.element.id) { index, rule in
                        HStack {
                            Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(rule.enabled ? .green : .secondary)
                                .font(.caption)
                            Text(rule.description)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            deleteButton { dictionary.removeRule(at: IndexSet(integer: index)) }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        if index < dictionary.editRules.count - 1 { Divider().padding(.horizontal, 10) }
                    }
                }
                .listCard()
            }
        }
    }

    // MARK: - Helpers

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 36)
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.caption2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Style Preset Card

private struct StylePresetCard: View {
    let style: LanguageStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: style.icon)
                        .font(.system(size: 13))
                    Text(style.label)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(style.defaultPrompt)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - List Card Modifier

private struct ListCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

private extension View {
    func listCard() -> some View {
        modifier(ListCardModifier())
    }
}
