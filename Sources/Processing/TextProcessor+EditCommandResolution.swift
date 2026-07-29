import Foundation

extension TextProcessor {
    func resolveSpokenEditCommand(
        text: String,
        options: TextProcessingOptions,
        context: SpokenEditCommandResolutionContext = .unknown
    ) async -> SpokenEditCommand? {
        guard case .command(let command) = await resolveSpokenEditCommandResolution(
            text: text,
            options: options,
            context: context
        ) else {
            return nil
        }
        return command
    }

    func resolveSpokenEditCommandResolution(
        text: String,
        options: TextProcessingOptions,
        context: SpokenEditCommandResolutionContext = .unknown
    ) async -> SpokenEditCommandLLMResolution? {
        let transcript = TranscriptionSanitizer.normalizeInput(text)
        guard !transcript.isEmpty else { return nil }

        do {
            let generationOptions = editCommandResolutionOptions(for: transcript)
            let result = try await generateText(
                prompt: PromptBuilder.buildEditCommandResolverUserPrompt(
                    text: transcript,
                    inputLanguage: options.inputLanguage,
                    context: context
                ),
                systemPrompt: systemPromptWithPersonalContext(
                    PromptBuilder.buildEditCommandResolverSystemPrompt(
                        inputLanguage: options.inputLanguage
                    ),
                    inputLanguage: options.inputLanguage
                ),
                options: options,
                maxTokens: generationOptions.maxTokens,
                temperature: generationOptions.temperature
            )
            let resolution = SpokenEditCommandLLMResolver.resolution(from: result)
            if case .command = resolution {
                Log.info("[TextProcessor] LLM resolved a spoken edit command")
            }
            return resolution
        } catch {
            Log.error("[TextProcessor] LLM edit command resolution failed: \(error.localizedDescription)")
            return nil
        }
    }

    func editCommandResolutionOptions(for text: String) -> GenerationOptions {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let maxTokens = characterCount > 160 ? 384 : 256
        return GenerationOptions(maxTokens: maxTokens, temperature: 0)
    }
}

enum SpokenEditCommandLLMResolver {
    static func resolution(from text: String) -> SpokenEditCommandLLMResolution? {
        var latestResolution: SpokenEditCommandLLMResolution?
        var fallbackResolution: SpokenEditCommandLLMResolution?
        for data in jsonObjectDataCandidates(from: text) {
            guard let resolution = try? JSONDecoder().decode(Resolution.self, from: data),
                  resolution.hasAction else {
                continue
            }
            guard let resolved = resolvedAction(from: resolution) else { continue }
            if case .command = resolved {
                latestResolution = resolved
            } else if isCompleteRejectionCandidate(resolution) {
                latestResolution = resolved
            } else {
                fallbackResolution = resolved
            }
        }
        return latestResolution ?? fallbackResolution
    }

    static func command(from text: String) -> SpokenEditCommand? {
        guard case .command(let command) = resolution(from: text) else {
            return nil
        }
        return command
    }
}

private extension SpokenEditCommandLLMResolver {
    struct Resolution: Decodable {
        let action: LLMActionValue?
        let intent: LLMTextValue?
        let target: LLMTargetValue?
        let replacement: LLMReplacementValue?
        let confidence: LLMNumericConfidence?
        let hasAction: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: LLMResolutionCodingKey.self)
            hasAction = container.hasCaseInsensitiveKey(anyOf: LLMResolutionFieldAlias.action)
            action = try container.decodeIfPresentCaseInsensitive(LLMActionValue.self, forAnyKey: LLMResolutionFieldAlias.action)
            intent = try container.decodeIfPresentCaseInsensitive(LLMTextValue.self, forAnyKey: LLMResolutionFieldAlias.intent)
            target = try container.decodeIfPresentCaseInsensitive(LLMTargetValue.self, forAnyKey: LLMResolutionFieldAlias.target)
            replacement = try container.decodeIfPresentCaseInsensitive(LLMReplacementValue.self, forAnyKey: LLMResolutionFieldAlias.replacement)
            confidence = try container.decodeIfPresentCaseInsensitive(LLMNumericConfidence.self, forAnyKey: LLMResolutionFieldAlias.confidence)
        }
    }

    static func resolvedAction(from resolution: Resolution) -> SpokenEditCommandLLMResolution? {
        let action = normalizedAction(resolution.action?.text, target: resolution.target?.text)
        if action == "none" {
            return SpokenEditCommandLLMResolution.none
        }

        guard let confidence = resolution.confidence?.value else {
            return SpokenEditCommandLLMResolution.none
        }
        guard confidence >= minimumConfidence else {
            return SpokenEditCommandLLMResolution.none
        }

        switch action {
        case "replace_last", "replacelast":
            guard emptyPayload(resolution.intent?.text),
                  let command = replacementCommand(resolution.replacement?.text, command: SpokenEditCommand.replaceLast) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(command)
        case "replace_selection", "replaceselection":
            guard emptyPayload(resolution.intent?.text),
                  let command = replacementCommand(resolution.replacement?.text, command: SpokenEditCommand.replaceSelection) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(command)
        case "rewrite_last", "rewritelast":
            guard emptyPayload(resolution.replacement?.text),
                  let intent = SelectionRewriteIntent.llmValue(resolution.intent?.text) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(.rewriteLast(intent))
        case "rewrite_selection", "rewriteselection":
            guard emptyPayload(resolution.replacement?.text),
                  let intent = SelectionRewriteIntent.llmValue(resolution.intent?.text) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(.rewriteSelection(intent))
        case "delete_selection", "deleteselection":
            guard emptyPayload(resolution.intent?.text), emptyPayload(resolution.replacement?.text) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(.deleteSelection)
        case "undo_last_insertion", "undolastinsertion":
            guard emptyPayload(resolution.intent?.text), emptyPayload(resolution.replacement?.text) else {
                return SpokenEditCommandLLMResolution.none
            }
            return .command(.undoLastInsertion)
        default:
            return SpokenEditCommandLLMResolution.none
        }
    }

    static func isCompleteRejectionCandidate(_ resolution: Resolution) -> Bool {
        let action = normalizedAction(resolution.action?.text, target: resolution.target?.text)
        if action == "none" {
            return true
        }
        guard let confidence = resolution.confidence?.value,
              (0...1).contains(confidence) else {
            return false
        }

        switch action {
        case "replace_last", "replacelast", "replace_selection", "replaceselection":
            return emptyPayload(resolution.intent?.text)
                && !cleanReplacementPayload(resolution.replacement?.text).isEmpty
        case "rewrite_last", "rewritelast", "rewrite_selection", "rewriteselection":
            return emptyPayload(resolution.replacement?.text)
                && SelectionRewriteIntent.llmValue(resolution.intent?.text) != nil
        case "delete_selection", "deleteselection", "undo_last_insertion", "undolastinsertion":
            return emptyPayload(resolution.intent?.text)
                && emptyPayload(resolution.replacement?.text)
        default:
            return false
        }
    }

    static let minimumConfidence = 0.75

    static func emptyPayload(_ rawValue: String?) -> Bool {
        normalizedIdentifier(rawValue).isEmpty || normalizedIdentifier(rawValue) == "null"
    }

    static func replacementCommand(
        _ rawReplacement: String?,
        command: (String) -> SpokenEditCommand
    ) -> SpokenEditCommand? {
        let replacement = cleanReplacementPayload(rawReplacement)
        return replacement.isEmpty ? nil : command(replacement)
    }

    static func cleanReplacementPayload(_ rawReplacement: String?) -> String {
        SpokenEditCommandPayloadCleaner.cleanReplacement(rawReplacement ?? "")
    }

    static func jsonObjectDataCandidates(from text: String) -> [Data] {
        LLMStructuredOutput.jsonObjectDataCandidates(from: text)
    }
}

extension SelectionRewriteIntent {
    static func llmValue(_ rawValue: String?) -> SelectionRewriteIntent? {
        let customInstruction = customInstructionValue(rawValue)
        guard !customInstruction.isEmpty else { return nil }
        if let preset = presetLLMValue(rawValue) {
            return preset
        }
        return .custom(customInstruction)
    }

    private static func presetLLMValue(_ rawValue: String?) -> SelectionRewriteIntent? {
        switch normalizedIdentifier(rawValue) {
        case "formal": return .formal
        case "casual": return .casual
        case "expand": return .expand
        case "title": return .title
        case "key_points", "keypoints", "key_point", "keypoint", "main_points", "mainpoints": return .keyPoints
        case "decisions": return .decisions
        case "questions": return .questions
        case "risks": return .risks
        case "deadlines": return .deadlines
        case "owners": return .owners
        case "meeting_notes", "meetingnotes", "meeting_note", "meetingnote", "meeting_summary", "meetingsummary": return .meetingNotes
        case "reply": return .reply
        case "reply_brief", "replybrief": return .replyBrief
        case "reply_formal", "replyformal": return .replyFormal
        case "reply_friendly", "replyfriendly": return .replyFriendly
        case "reply_in_english", "replyinenglish", "reply_english", "replyenglish": return .replyInEnglish
        case "reply_in_chinese", "replyinchinese", "reply_chinese", "replychinese": return .replyInChinese
        case "reply_accept", "replyaccept": return .replyAccept
        case "reply_decline", "replydecline": return .replyDecline
        case "reply_clarify", "replyclarify": return .replyClarify
        case "summary": return .summary
        case "concise": return .concise
        case "proofread": return .proofread
        case "table": return .table
        case "bullet_list", "bulletlist", "bullets", "bullet_points", "bulletpoints": return .bulletList
        case "numbered_list", "numberedlist", "numbered_points", "numberedpoints": return .numberedList
        case "action_items", "actionitems", "action_item", "actionitem", "todos", "todo_list", "todolist": return .actionItems
        case "checklist": return .checklist
        case "translate_to_english", "translatetoenglish", "translate_english", "translateenglish": return .translateToEnglish
        case "translate_to_chinese", "translatetochinese", "translate_chinese", "translatechinese": return .translateToChinese
        default: return nil
        }
    }

    private static func customInstructionValue(_ rawValue: String?) -> String {
        let cleaned = (rawValue ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, normalizedIdentifier(cleaned) != "null" else { return "" }

        return String(cleaned.prefix(280)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func normalizedIdentifier(_ rawValue: String?) -> String {
    (rawValue ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
}
