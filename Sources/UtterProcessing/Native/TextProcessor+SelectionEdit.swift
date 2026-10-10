import UtterContracts
import Foundation

extension TextProcessor {
    package func processSelectionEdit(
        selectedText: String,
        intent: SelectionRewriteIntent,
        options: TextProcessingOptions,
        spokenCommand: String = "",
        memoryContext: String = "",
        inputContext: InputContext? = nil,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) async -> String {
        let options = await effectiveProviderOptions(options)
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else { return "" }
        let generationOptions = selectionEditOptions(for: trimmedSelection, intent: intent)

        do {
            let baseUserPrompt = selectionEditPrompt(
                selectedText: trimmedSelection,
                intent: intent,
                inputLanguage: options.inputLanguage,
                spokenCommand: spokenCommand,
                memoryContext: memoryContext,
                inputContext: inputContext
            )
            let personal = personalContextSections(
                inputLanguage: options.inputLanguage,
                dictionarySnapshot: dictionarySnapshot,
                transcript: trimmedSelection
            )
            let userPrompt = personal.isEmpty
                ? baseUserPrompt
                : personal.joined(separator: "\n\n") + "\n\n" + baseUserPrompt
            let result = try await generateText(
                prompt: userPrompt,
                systemPrompt: selectionEditSystemPrompt(inputLanguage: options.inputLanguage),
                options: options,
                maxTokens: generationOptions.maxTokens,
                temperature: generationOptions.temperature
            )
            return cleanSelectionEditOutput(result, inputLanguage: options.inputLanguage)
        } catch {
            log.error("[TextProcessor] Selection edit failed: \(error.localizedDescription)")
            return ""
        }
    }

    /// Selection-edit prompts advertise the same final_text JSON contract as
    /// command prompts, so the envelope is honored here too.
    package func cleanSelectionEditOutput(_ text: String, inputLanguage: InputLanguage) -> String {
        cleanCommandGeneratedOutput(text, inputLanguage: inputLanguage)
    }
}

extension TextProcessor {
    package func selectionEditOptions(for text: String, intent: SelectionRewriteIntent) -> GenerationOptions {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let size = selectionEditSize(for: characterCount)

        let maxTokens: Int
        switch intent {
        case .title:
            maxTokens = 96
        case .replyBrief:
            maxTokens = 192
        case .expand, .reply, .replyFormal, .replyFriendly, .replyInEnglish, .replyInChinese,
                .replyAccept, .replyDecline, .replyClarify:
            maxTokens = [384, 768, 1024][size]
        case .meetingNotes:
            maxTokens = [640, 1024, 1536][size]
        case .keyPoints, .decisions, .questions, .risks, .deadlines, .owners, .table,
                .bulletList, .numberedList, .actionItems, .checklist:
            maxTokens = [384, 640, 1024][size]
        case .formal, .casual, .summary, .concise, .proofread, .translateToEnglish, .translateToChinese:
            maxTokens = [256, 512, 768][size]
        case .custom:
            maxTokens = [384, 768, 1280][size]
        }

        let temperature: Double
        switch intent {
        case .keyPoints, .decisions, .questions, .risks, .deadlines, .owners, .proofread,
                .table, .bulletList, .numberedList, .actionItems, .checklist:
            temperature = 0.10
        case .casual, .replyFriendly:
            temperature = 0.18
        case .custom:
            temperature = 0.15
        default:
            temperature = 0.15
        }

        return GenerationOptions(maxTokens: maxTokens, temperature: temperature)
    }

    package func selectionEditSize(for characterCount: Int) -> Int {
        switch characterCount {
        case 0...120:
            return 0
        case 121...360:
            return 1
        default:
            return 2
        }
    }
}
