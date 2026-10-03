import UtterContracts
import Foundation

enum PromptBuilder {
    static func buildSystemPrompt(
        style: LanguageStyle,
        stylePrompt: String,
        screenContext: String = "",
        screenImageAvailable: Bool = false,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        formatKind: TextFormatKind? = nil,
        inputLanguage: InputLanguage = .chinese,
        useCustomSystemPrompt: Bool? = nil,
        customSystemPrompt: String? = nil
    ) -> String {
        buildFormattingAssembly(
            style: style,
            stylePrompt: stylePrompt,
            screenContext: screenContext,
            screenImageAvailable: screenImageAvailable,
            memoryContext: memoryContext,
            inputContext: inputContext,
            formatKind: formatKind,
            inputLanguage: inputLanguage,
            useCustomSystemPrompt: useCustomSystemPrompt,
            customSystemPrompt: customSystemPrompt
        ).systemPrompt
    }

    static func buildFormattingAssembly(
        style: LanguageStyle,
        stylePrompt: String,
        screenContext: String = "",
        screenImageAvailable: Bool = false,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        formatKind: TextFormatKind? = nil,
        inputLanguage: InputLanguage = .chinese,
        useCustomSystemPrompt: Bool? = nil,
        customSystemPrompt: String? = nil
    ) -> PromptAssembly {
        var stableParts = promptParts(
            useCustomSystemPrompt: useCustomSystemPrompt
                ?? AppSettings.shared.useCustomSystemPrompt,
            customSystemPrompt: customSystemPrompt
                ?? AppSettings.shared.customSystemPrompt,
            style: style,
            stylePrompt: stylePrompt,
            inputLanguage: inputLanguage
        )
        if let formatKind {
            stableParts.append(PromptCatalog.formatContractSection(
                kind: formatKind,
                inputLanguage: inputLanguage
            ))
        }
        let volatileParts = PromptCatalog.processingContextSections(
            screenContext: screenContext,
            screenImageAvailable: screenImageAvailable,
            memoryContext: memoryContext,
            inputContext: inputContext,
            inputLanguage: inputLanguage
        )

        return PromptAssembly(
            stablePrefix: stableParts.joined(separator: "\n\n"),
            volatileContext: volatileParts.joined(separator: "\n\n")
        )
    }

    static func buildUserPrompt(text: String, inputLanguage: InputLanguage = .chinese) -> String {
        PromptCatalog.userPrompt(text: text, inputLanguage: inputLanguage)
    }

    static func buildCustomUserPrompt(
        text: String,
        inputLanguage: InputLanguage = .chinese
    ) -> String {
        PromptCatalog.customUserPrompt(text: text, inputLanguage: inputLanguage)
    }

    static func buildCommandUserPrompt(text: String, inputLanguage: InputLanguage = .chinese) -> String {
        PromptCatalog.commandUserPrompt(text: text, inputLanguage: inputLanguage)
    }

    static func buildEditCommandResolverSystemPrompt(inputLanguage: InputLanguage = .chinese) -> String {
        PromptCatalog.editCommandResolverSystemPrompt(inputLanguage: inputLanguage)
    }

    static func buildEditCommandResolverUserPrompt(
        text: String,
        inputLanguage: InputLanguage = .chinese,
        context: SpokenEditCommandResolutionContext = .unknown
    ) -> String {
        PromptCatalog.editCommandResolverUserPrompt(text: text, inputLanguage: inputLanguage, context: context)
    }

    static func buildCommandSystemPrompt(
        screenContext: String,
        screenImageAvailable: Bool = false,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        inputLanguage: InputLanguage = .chinese
    ) -> String {
        buildCommandAssembly(
            screenContext: screenContext,
            screenImageAvailable: screenImageAvailable,
            memoryContext: memoryContext,
            inputContext: inputContext,
            inputLanguage: inputLanguage
        ).systemPrompt
    }

    static func buildCommandAssembly(
        screenContext: String,
        screenImageAvailable: Bool = false,
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        inputLanguage: InputLanguage = .chinese
    ) -> PromptAssembly {
        let stablePrefix = PromptCatalog.commandSystemPrompt(inputLanguage: inputLanguage)
        let volatileParts = PromptCatalog.commandContextSections(
            screenContext: screenContext,
            screenImageAvailable: screenImageAvailable,
            memoryContext: memoryContext,
            inputContext: inputContext,
            inputLanguage: inputLanguage
        )
        return PromptAssembly(
            stablePrefix: stablePrefix,
            volatileContext: volatileParts.joined(separator: "\n\n")
        )
    }
}

private extension PromptBuilder {
    static func promptParts(
        useCustomSystemPrompt: Bool,
        customSystemPrompt: String,
        style: LanguageStyle,
        stylePrompt: String,
        inputLanguage: InputLanguage
    ) -> [String] {
        let customSystemPrompt = customSystemPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if useCustomSystemPrompt, !customSystemPrompt.isEmpty {
            return [
                customSystemPrompt,
                PromptCatalog.customSystemPromptOutputContract(inputLanguage: inputLanguage),
            ]
        }

        var parts = [
            PromptCatalog.baseSystemPrompt(inputLanguage: inputLanguage),
            PromptCatalog.asrQualityRules(inputLanguage: inputLanguage),
        ]
        if style.usesCustomPrompt {
            if let customStyle = PromptStylePrompts.customStyleSection(
                stylePrompt: stylePrompt,
                inputLanguage: inputLanguage
            ) {
                parts.append(customStyle)
            }
            return parts
        }

        parts.append(PromptStylePrompts.section(style: style, inputLanguage: inputLanguage))
        let fewShots = PromptStylePrompts.fewShotSection(style: style, inputLanguage: inputLanguage)
        if !fewShots.isEmpty {
            parts.append(fewShots)
        }
        return parts
    }
}
