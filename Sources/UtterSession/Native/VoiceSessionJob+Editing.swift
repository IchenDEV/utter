import Foundation
import UtterContracts
import UtterMediaContracts

extension VoiceSessionJob {
    func performSelectedRewrite(_ request: ProcessingRequest, control: any SessionJobControl) async throws -> SessionCompletion {
        let selectedTarget = try selectionTarget()
        let (text, outcome) = try await rewrite(selectedTarget.selectedText ?? "", instruction: .custom(request.text),
            request: request, control: control)
        try await prepareSelectionEdit(text, instruction: request.text, target: selectedTarget, control: control)
        let acceptance = try await deliver(.replaceSelection(text), target: selectedTarget, control: control)
        return SessionCompletion(transcript: request.text, text: text, acceptance: acceptance,
            outputMutation: selectedOutputMutation(acceptance), generationOutcome: outcome)
    }

    func performSpokenEdit(_ request: ProcessingRequest, recipe: any ModeRecipeService,
                          control: any SessionJobControl) async throws -> SessionCompletion? {
        let selected = target?.selectedText
        let recent = recentOutput?.text
        let availability = SpokenEditCommandResolutionContext(
            lastInsertion: recentOutput?.anchor?.isCurrent == true
                && recentOutput?.anchor?.target.processIdentifier == target?.processIdentifier ? .available : .unavailable,
            selectedText: selected == nil ? .unknown : selected?.isEmpty == false ? .available : .unavailable,
            lastInsertionPreview: SpokenEditCommandResolutionContext.preview(recent),
            selectedTextPreview: SpokenEditCommandResolutionContext.preview(selected))
        let resolution = try await recipe.resolveEditCommand(request, context: availability)
        try check(control)
        guard case .command(let command) = resolution,
              SpokenEditEvidence.namesTargetAndOperation(command, transcript: request.text) else { return nil }
        let outputCommand: DeliveryCommand
        let outputTarget: (any OutputTargetLease)?
        let text: String
        var generationOutcome: EspressoGenerationOutcome?
        let recordsHistory: Bool
        switch command {
        case .replaceLast(let replacement):
            let anchor = try recentAnchor()
            text = try replacementText(recipe.cleanReplacement(replacement, language: settings.inputLanguage))
            outputCommand = .replaceAnchor(text, anchor)
            outputTarget = anchor.target
            recordsHistory = true
        case .rewriteLast(let instruction):
            let anchor = try recentAnchor()
            (text, generationOutcome) = try await rewrite(anchor.text, instruction: instruction, request: request, control: control)
            outputCommand = .replaceAnchor(text, anchor)
            outputTarget = anchor.target
            recordsHistory = true
        case .replaceSelection(let replacement):
            outputTarget = try selectionTarget()
            text = try replacementText(recipe.cleanReplacement(replacement, language: settings.inputLanguage))
            outputCommand = .replaceSelection(text)
            recordsHistory = false
        case .rewriteSelection(let instruction):
            let selectedTarget = try selectionTarget()
            (text, generationOutcome) = try await rewrite(selectedTarget.selectedText ?? "", instruction: instruction, request: request, control: control)
            outputCommand = .replaceSelection(text)
            outputTarget = selectedTarget
            recordsHistory = false
        case .deleteSelection:
            outputTarget = try selectionTarget()
            text = ""
            outputCommand = .deleteSelection
            recordsHistory = false
        case .undoLastInsertion:
            let anchor = try recentAnchor()
            text = ""
            if let edit = recentOutput?.selectionEdit {
                guard edit.anchor === anchor, edit.replacement == anchor.text,
                      dependencies.outputs?.consumeSelectionEdit(edit.operationID) == true else {
                    throw DeliveryError.invalidTarget
                }
                outputCommand = .replaceAnchor(edit.originalSelection, anchor)
            } else {
                outputCommand = .undoAnchor(anchor)
            }
            outputTarget = anchor.target
            recordsHistory = false
        }
        if case .replaceSelection = outputCommand {
            try await prepareSelectionEdit(text, instruction: request.text, target: outputTarget, control: control)
        }
        control.update(phase: .delivering, transcript: request.text)
        let acceptance = try await deliver(outputCommand, target: outputTarget, control: control)
        let isSelection: Bool
        if case .replaceSelection = outputCommand { isSelection = true } else { isSelection = false }
        return SessionCompletion(transcript: request.text, text: text, acceptance: acceptance,
            record: !isSelection && (recordsHistory || !acceptance.isAccepted) ? InputRecord(id: intent.id, date: Date(), rawText: request.text,
                processedText: text, wasProcessed: true, context: request.inputContext) : nil,
            outputMutation: isSelection ? selectedOutputMutation(acceptance) : .remember, generationOutcome: generationOutcome)
    }

    private func recentAnchor() throws -> any OutputAnchor {
        guard let anchor = recentOutput?.anchor, anchor.isCurrent,
              anchor.target.processIdentifier == target?.processIdentifier else {
            throw DeliveryError.invalidTarget
        }
        return anchor
    }

    private func selectionTarget() throws -> any OutputTargetLease {
        guard let target, target.isCurrent, target.selectedText?.isEmpty == false else { throw DeliveryError.invalidTarget }
        return target
    }

    private func replacementText(_ replacement: String) throws -> String {
        let text = SpokenEditCommandPayloadCleaner.cleanReplacement(replacement)
        guard !text.isEmpty else { throw IntegrationError.noSpeechDetected }
        return text
    }

    private func rewrite(_ text: String, instruction: SelectionRewriteIntent, request: ProcessingRequest,
                         control: any SessionJobControl) async throws -> (String, EspressoGenerationOutcome?) {
        let recipe = try await dependencies.recipes.create(id: editRecipeID, request: ())
        try check(control)
        let measurement = control.beginStage(.processing)
        defer { control.endStage(measurement) }
        let output = try await recipe.process(ProcessingRequest(mode: .selectionEdit(instruction, spokenCommand: request.text),
            text: text, options: options, dictionary: settings.dictionary, screenContext: request.screenContext,
            screenImage: request.screenImage, memoryContext: request.memoryContext, inputContext: request.inputContext))
        try check(control)
        return (try replacementText(output.text), output.generationOutcome)
    }
}
