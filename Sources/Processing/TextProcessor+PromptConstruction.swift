import Foundation

extension TextProcessor {
    func formattingUserPrompt(
        text: String,
        options: TextProcessingOptions
    ) -> String {
        switch options.fidelityPolicy {
        case .faithfulCorrection:
            return PromptBuilder.buildUserPrompt(
                text: text,
                inputLanguage: options.inputLanguage
            )
        case .boundedCustomTransformation:
            return PromptBuilder.buildCustomUserPrompt(
                text: text,
                inputLanguage: options.inputLanguage
            )
        }
    }

    func formattingSystemPrompt(
        options: TextProcessingOptions,
        screenContext: String,
        screenImageAvailable: Bool,
        memoryContext: String,
        inputContext: InputContext?,
        formatKind: TextFormatKind? = nil,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil,
        transcript: String = ""
    ) -> String {
        systemPromptWithPersonalContext(
            PromptBuilder.buildSystemPrompt(
                style: options.languageStyle,
                stylePrompt: options.customStylePrompt,
                screenContext: screenContext,
                screenImageAvailable: screenImageAvailable,
                memoryContext: memoryContext,
                inputContext: inputContext,
                formatKind: formatKind,
                inputLanguage: options.inputLanguage,
                useCustomSystemPrompt: options.useCustomSystemPrompt,
                customSystemPrompt: options.customSystemPrompt
            ),
            inputLanguage: options.inputLanguage,
            dictionarySnapshot: dictionarySnapshot,
            transcript: transcript
        )
    }

    func commandSystemPrompt(
        options: TextProcessingOptions,
        screenContext: String,
        screenImageAvailable: Bool,
        memoryContext: String,
        inputContext: InputContext?,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil,
        transcript: String = ""
    ) -> String {
        systemPromptWithPersonalContext(
            PromptBuilder.buildCommandSystemPrompt(
                screenContext: screenContext,
                screenImageAvailable: screenImageAvailable,
                memoryContext: memoryContext,
                inputContext: inputContext,
                inputLanguage: options.inputLanguage
            ),
            inputLanguage: options.inputLanguage,
            dictionarySnapshot: dictionarySnapshot,
            transcript: transcript
        )
    }

    func systemPromptWithPersonalContext(
        _ systemPrompt: String,
        inputLanguage: InputLanguage,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil,
        transcript: String = ""
    ) -> String {
        let snapshot = dictionarySnapshot ?? PersonalDictionary.shared.snapshot(settings: .shared)
        let extraSections = [
            PromptCatalog.activeIndustryLexiconSection(
                snapshot.industryLexicon.promptDescription(matching: transcript),
                industry: snapshot.industryLexicon.pack?.id,
                inputLanguage: inputLanguage
            ),
            PromptCatalog.activePersonalDictionarySection(
                snapshot.activeEntriesDescription,
                inputLanguage: inputLanguage
            ),
            PromptCatalog.activeEditRulesSection(
                snapshot.activeRulesDescription,
                inputLanguage: inputLanguage
            ),
        ].compactMap { $0 }

        guard !extraSections.isEmpty else { return systemPrompt }
        return ([systemPrompt] + extraSections).joined(separator: "\n\n")
    }
}
