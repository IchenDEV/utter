import Foundation
import UtterContracts
import UtterMediaContracts

extension VoiceSessionJob {
    func insertThenFormat(_ transcript: String, outputs: any SessionOutputStateService,
                          control: any SessionJobControl) async throws -> SessionCompletion {
        let direct = try await dependencies.recipes.create(id: directRecipeID, request: ())
        try check(control)
        let quick = try await direct.process(ProcessingRequest(mode: .direct, text: transcript,
            options: options, dictionary: settings.dictionary, inputContext: context))
        try check(control)
        let text = quick.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw IntegrationError.noSpeechDetected }
        control.update(phase: .delivering, transcript: transcript)
        let acceptance = try await deliver(.insert(text), target: target, control: control)
        let kind = dependencies.preparation.format(text: transcript, context: context).kind
        let record = InputRecord(id: intent.id, date: Date(), rawText: transcript, processedText: text,
            wasProcessed: false, context: context, formatKind: kind)
        guard acceptance.isAccepted else { return SessionCompletion(transcript: transcript, text: text, acceptance: acceptance, record: record) }
        let work = DeferredFormatWork(request: ProcessingRequest(mode: .formatting, text: transcript, options: options,
            dictionary: settings.dictionary, memoryContext: memoryContext, inputContext: context, formatKind: kind),
            recipeID: recipeID, outputs: outputs, recipes: dependencies.recipes, access: dependencies.access,
            screen: screenTask, authorize: authorize)
        if Task.isCancelled || revoked { work.revoke() }
        screenTask = nil
        return SessionCompletion(transcript: transcript, text: text, acceptance: acceptance, record: record, followup: work)
    }
}
