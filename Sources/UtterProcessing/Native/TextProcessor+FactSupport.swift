import Foundation
import UtterContracts

extension TextProcessor {
    func validateTransformation(_ candidate: String, source: String, terms: [String],
                                options: TextProcessingOptions) async throws -> String {
        let faithful = options.fidelityPolicy == .faithfulCorrection
        let violation = TranscriptFidelityGuard.violation(source: source, candidate: candidate,
            protectedTerms: terms, inputLanguage: options.inputLanguage, enforceSemanticFidelity: faithful)
        if let violation { return rejectedTransformation(candidate, source: source, reason: violation) }
        if faithful {
            ProcessingObservations.current?.record(source: source, candidate: candidate,
                decision: ProcessingDecision(.accepted))
            return candidate
        }
        let prompt = PromptCatalog.factSupportUserPrompt(source: source, candidate: candidate)
        // Never check a truncated source. This conservative input ceiling also
        // bounds custom transformations on providers without context metadata.
        guard prompt.utf8.count + PromptCatalog.factSupportSystemPrompt.utf8.count <= 12_000 else {
            return rejectedTransformation(candidate, source: source, reason: "fact_check_input_limit")
        }
        var checkOptions = options
        checkOptions.textProviderID = ProcessingObservations.current?.lastSuccessfulProviderID ?? options.textProviderID
        checkOptions.fallbackToMLXOnEspressoFailure = false
        do {
            let result = try await ProcessingObservations.$generationStage.withValue(.factSupport) {
                try await generateText(prompt: prompt, systemPrompt: PromptCatalog.factSupportSystemPrompt,
                    options: checkOptions, maxTokens: 768, temperature: 0)
            }
            try Task.checkCancellation()
            guard FactSupportVerdict.accepts(result) else {
                return rejectedTransformation(candidate, source: source, reason: "fact_support_unconfirmed")
            }
            ProcessingObservations.current?.record(source: source, candidate: candidate,
                decision: ProcessingDecision(.accepted))
            return candidate
        } catch {
            try Task.checkCancellation()
            return rejectedTransformation(candidate, source: source, reason: "fact_check_failed")
        }
    }

    private func rejectedTransformation(_ candidate: String, source: String, reason: String) -> String {
        ProcessingObservations.current?.record(source: source, candidate: candidate,
            decision: ProcessingDecision(.fallback, reason: reason))
        log.error("[TextProcessor] rejected formatting output: \(reason); keeping source transcript")
        return source
    }
}
