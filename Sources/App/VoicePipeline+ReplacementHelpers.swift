import Foundation

@MainActor
extension VoicePipeline {
    func immediateInsertText(
        from raw: String,
        inputLanguage: InputLanguage,
        dictionarySnapshot: PersonalDictionarySnapshot
    ) -> String {
        let cleaned = textProcessor.prepareForFormatting(
            text: raw,
            inputLanguage: inputLanguage,
            dictionarySnapshot: dictionarySnapshot
        )
        let fallback = textProcessor.basicClean(
            text: raw,
            inputLanguage: inputLanguage,
            dictionarySnapshot: dictionarySnapshot
        )
        if !cleaned.isEmpty { return cleaned }
        if !fallback.isEmpty { return fallback }
        return ""
    }

    func replacementCopyMessage(for reason: DeferredReplacementCopyReason) -> String {
        switch reason {
        case .expired:
            return L("pipeline.replacement_copied_expired")
        case .missingTarget:
            return L("pipeline.replacement_copied_missing_target")
        case .appChanged:
            return L("pipeline.replacement_copied_app_changed")
        case .notReady:
            return L("pipeline.replacement_not_ready")
        }
    }
}
