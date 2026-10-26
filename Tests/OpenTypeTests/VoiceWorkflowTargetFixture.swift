import Foundation
import UtterContracts
import UtterMediaContracts
import UtterProcessing

@MainActor
final class WorkflowTarget: OutputTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 123
    var context: InputContext {
        InputContext(appName: "Editor", bundleIdentifier: "fixture.editor", selectedText: selectedText.map { String($0.prefix(500)) },
            outputMode: .processed, inputLanguage: .english, source: .menuBar)
    }
    var selectedText: String?
    var isValid = true
    var isCurrent = true
}

@MainActor
final class WorkflowCorrection: CorrectionControlService {
    var started: [UUID] = []
    func start(seed: CorrectionCaptureSeed, recordID: UUID) { started.append(recordID) }
    func finishCurrentSession() {}
    func cancelCurrentSession() {}
}

@MainActor
final class WorkflowRecipe: ModeRecipeService {
    var selectionProcessor: ((ProcessingRequest) async throws -> ProcessingResult)?
    var failure: Error?
    var generatedText: String?
    var generationOutcome: EspressoGenerationOutcome?
    var requests: [ProcessingRequest] = []
    var resolution: SpokenEditCommandLLMResolution?
    var resolutionContexts: [SpokenEditCommandResolutionContext] = []
    var holdFormatting = false
    var confirmsTranslation = true
    var translationProofTarget: TranslationLanguage?
    var formatting = false
    private var formattingWaiter: CheckedContinuation<Void, Never>?
    func resolveEditCommand(_ request: ProcessingRequest, context: SpokenEditCommandResolutionContext) async throws -> SpokenEditCommandLLMResolution? {
        resolutionContexts.append(context)
        return resolution
    }
    func process(_ request: ProcessingRequest) async throws -> ProcessingResult {
        requests.append(request)
        if let failure { throw failure }
        if case .selectionEdit(let intent, let command) = request.mode {
            if let selectionProcessor { return try await selectionProcessor(request) }
            let candidate = try await SelectionEditRecipe.candidate(selectedText: request.text, intent: intent,
                inputLanguage: request.options.inputLanguage, spokenCommand: command,
                memoryContext: request.memoryContext, inputContext: request.inputContext,
                dictionarySnapshot: request.dictionary) { [self] _, _, _ in generatedText ?? request.text + " Formatted." }
            return ProcessingResult(text: candidate, generationOutcome: generationOutcome)
        }
        if let generatedText { return ProcessingResult(text: generatedText) }
        if request.mode == .direct { return ProcessingResult(text: request.text) }
        if request.mode == .formatting {
            formatting = true
            if holdFormatting { await withCheckedContinuation { formattingWaiter = $0 } }
        }
        if case .translation(let target) = request.mode, confirmsTranslation {
            let language = translationProofTarget ?? target
            let assessment = TranslationAssessment.assess(target: language,
                hasLinguisticContent: true, scores: [language.rawValue: 1])
            return ProcessingResult(text: request.text + " Formatted.",
                decision: ProcessingDecision(.accepted, translation: assessment))
        }
        return ProcessingResult(text: request.text + " Formatted.", generationOutcome: generationOutcome)
    }
    func releaseFormatting() { formattingWaiter?.resume(); formattingWaiter = nil }
}
