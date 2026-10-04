import Foundation
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
final class VoiceSessionJob: SessionJob {
    let intent: SessionIntent
    var input: SessionInput
    let settings: VoiceInputSettings
    let options: TextProcessingOptions
    let mode: TextProcessingMode
    let recipeID: String
    let directRecipeID: String
    let editRecipeID: String
    let speechDescriptor: ProviderDescriptor?
    let speechFiles: FrozenModelFiles?
    let context: InputContext
    let target: (any OutputTargetLease)?
    let recentOutput: RecentSessionOutput?
    let memoryContext: String
    let dependencies: VoiceWorkflowDependencies
    let authorize: () throws -> Void
    let callbacks = CallbackTasks()
    var engine: (any SpeechEngine)?
    var recording: (any OwnedRecording)?
    var delivery: (any PreparedDelivery)?
    var screenTask: Task<ScreenContextSnapshot, Never>?
    var revoked = false
    var capturing = false
    private var closed = false
    var settingsObservation: UUID?
    var credentialsObservation: UUID?
    var clientObservation: UUID?

    init(intent: SessionIntent, settings: VoiceInputSettings, options: TextProcessingOptions, mode: TextProcessingMode,
         recipeID: String, directRecipeID: String, editRecipeID: String,
         speechDescriptor: ProviderDescriptor?, speechFiles: FrozenModelFiles?, context: InputContext,
         target: (any OutputTargetLease)?, recentOutput: RecentSessionOutput?, memoryContext: String,
         dependencies: VoiceWorkflowDependencies, authorize: @escaping () throws -> Void) {
        self.intent = intent
        self.input = intent.input
        self.settings = settings
        self.options = options
        self.mode = mode
        self.recipeID = recipeID
        self.directRecipeID = directRecipeID
        self.editRecipeID = editRecipeID
        self.speechDescriptor = speechDescriptor
        self.speechFiles = speechFiles
        self.context = context
        self.target = target
        self.recentOutput = recentOutput
        self.memoryContext = memoryContext
        self.dependencies = dependencies
        self.authorize = authorize
    }

    func bind(input: SessionInput) throws {
        guard self.input == .unselected, input != .unselected, !revoked, !closed else {
            throw IntegrationError.invalidSessionState
        }
        self.input = input
    }

    func run(control: any SessionJobControl) async throws -> SessionCompletion {
        try await dependencies.access.withAccess {
            do {
                let completion = try await execute(control: control)
                await close()
                return completion
            } catch {
                await close()
                throw error
            }
        }
    }

    private func execute(control: any SessionJobControl) async throws -> SessionCompletion {
        try check(control)
        dependencies.correction?.finishCurrentSession()
        let transcript = try await transcription(control: control)
        control.update(phase: .processing, transcript: transcript)
        if intent.clientID == nil, mode == .formatting, settings.enableInstantInsert,
           let outputs = dependencies.outputs {
            return try await insertThenFormat(transcript, outputs: outputs, control: control)
        }
        let screen = await screenTask?.value ?? .empty
        try check(control)
        let inputContext = contextWithScreen(screen.text)
        let formatKind = mode == .formatting ? dependencies.preparation.format(text: transcript, context: inputContext).kind : nil
        let recipe = try await dependencies.recipes.create(id: recipeID, request: ())
        try check(control)
        let request = ProcessingRequest(mode: mode, text: processingText(transcript), options: options,
            dictionary: settings.dictionary, screenContext: screen.text, screenImage: screen.image,
            memoryContext: memoryContext, inputContext: inputContext, formatKind: formatKind)
        if intent.clientID == nil, mode == .command,
           let edited = try await performSpokenEdit(request, recipe: recipe, control: control) { return edited }
        let output = try await recipe.process(request)
        try check(control)
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw IntegrationError.operationFailed }
        let acceptance: SessionAcceptance
        if intent.clientID != nil {
            acceptance = .returnedText
        } else {
            control.update(phase: .delivering, transcript: transcript)
            let command: DeliveryCommand
            if case .selectionEdit = mode {
                guard target?.selectedText?.isEmpty == false else { throw DeliveryError.invalidTarget }
                command = .replaceSelection(text)
            } else { command = target == nil ? .clipboard(text) : .insert(text) }
            acceptance = try await deliver(command, target: target, control: control)
        }
        return SessionCompletion(transcript: transcript, text: text, acceptance: acceptance,
            record: InputRecord(id: intent.id, date: Date(), rawText: transcript, processedText: text, wasProcessed: mode != .direct,
                                context: inputContext, formatKind: formatKind))
    }

    func check(_ control: any SessionJobControl) throws {
        try Task.checkCancellation()
        guard !revoked, control.isCurrent else { throw CancellationError() }
        try authorize()
    }

    func revoke() {
        revoked = true
        callbacks.revoke()
        screenTask?.cancel()
        engine?.cancelListening()
    }

    func close() async {
        guard !closed else { return }
        closed = true
        detachAuthorization()
        revoke()
        await callbacks.close()
        if let screenTask { _ = await screenTask.value }
        await engine?.drainRecognition()
        await delivery?.close()
        await recording?.close()
        screenTask = nil
        recording = nil
        delivery = nil
        engine = nil
    }
}
