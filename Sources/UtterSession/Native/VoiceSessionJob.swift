import Foundation
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
final class VoiceSessionJob: SessionJob {
    let intent: SessionIntent
    let settings: VoiceInputSettings
    let options: TextProcessingOptions
    let mode: TextProcessingMode
    let recipeID: String
    let speechDescriptor: ProviderDescriptor
    let speechFiles: FrozenModelFiles
    let context: InputContext
    let target: (any OutputTargetLease)?
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

    init(intent: SessionIntent, settings: VoiceInputSettings, options: TextProcessingOptions, mode: TextProcessingMode,
         recipeID: String, speechDescriptor: ProviderDescriptor, speechFiles: FrozenModelFiles, context: InputContext,
         target: (any OutputTargetLease)?, dependencies: VoiceWorkflowDependencies, authorize: @escaping () throws -> Void) {
        self.intent = intent
        self.settings = settings
        self.options = options
        self.mode = mode
        self.recipeID = recipeID
        self.speechDescriptor = speechDescriptor
        self.speechFiles = speechFiles
        self.context = context
        self.target = target
        self.dependencies = dependencies
        self.authorize = authorize
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
        guard speechFiles.isCurrent else { throw IntegrationError.modelNotReady }
        dependencies.correction?.finishCurrentSession()
        let selected = try await dependencies.speech.create(id: settings.speech.providerID,
            request: SpeechProviderRequest(selection: settings.speech, modelFiles: speechFiles))
        engine = selected
        try check(control)
        try await selected.requestPermission()
        try check(control)
        await selected.prepare()
        try check(control)
        guard selected.isReady else { throw IntegrationError.modelNotReady }
        selected.configureRecognition(context: SpeechRecognitionContext(phrases: speechDescriptor.recognitionVocabulary == .personal
            ? settings.dictionary.personalRecognitionPhrases : settings.dictionary.recognitionPhrases))
        startScreenCapture()
        let audio = try await capture(using: selected, control: control)
        try check(control)
        control.update(phase: .transcribing, transcript: "")
        if let activity = audio.activity, !activity.hasMeaningfulAudio { throw IntegrationError.noSpeechDetected }
        guard try await dependencies.evidence.containsSpeech(at: audio.url) else { throw IntegrationError.noSpeechDetected }
        try check(control)
        let raw: String
        if audio.streaming {
            raw = try await selected.finishListening(audioURL: audio.url, language: settings.inputLanguage.whisperCode)
        } else {
            raw = try await selected.transcribe(audioURL: audio.url, language: settings.inputLanguage.whisperCode)
        }
        try check(control)
        guard let transcript = TranscriptionSanitizer.prepare(raw, audioActivity: audio.activity,
            recognitionPhrases: settings.dictionary.recognitionPhrases) else { throw IntegrationError.noSpeechDetected }
        control.update(phase: .processing, transcript: transcript)
        let screen = await screenTask?.value ?? .empty
        try check(control)
        let inputContext = contextWithScreen(screen.text)
        let formatKind = mode == .formatting ? TextFormatClassifier.classify(text: transcript, context: inputContext).kind : nil
        let memory = settings.enableMemory && mode != .direct
            ? dependencies.memory?.recentContext(limit: 5, windowMinutes: settings.memoryWindowMinutes, currentContext: inputContext) ?? "" : ""
        let recipe = try await dependencies.recipes.create(id: recipeID, request: ())
        try check(control)
        let output = try await recipe.process(ProcessingRequest(mode: mode, text: transcript, options: options,
            dictionary: settings.dictionary, screenContext: screen.text, screenImage: screen.image,
            memoryContext: memory, inputContext: inputContext, formatKind: formatKind))
        try check(control)
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw IntegrationError.operationFailed }
        let acceptance: SessionAcceptance
        if intent.clientID != nil {
            acceptance = .returnedText
        } else {
            control.update(phase: .delivering, transcript: transcript)
            let prepared = try dependencies.output.prepare(DeliveryRequest(id: intent.id,
                command: target == nil ? .clipboard(text) : .insert(text), target: target),
                isSessionCurrent: { [weak self, weak control] in
                    guard let self, let control else { return false }
                    return (try? self.check(control)) != nil
                })
            delivery = prepared
            acceptance = .delivery(await prepared.commit())
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
        revoke()
        await callbacks.close()
        if let screenTask { _ = await screenTask.value }
        await delivery?.close()
        await recording?.close()
        screenTask = nil
        recording = nil
        delivery = nil
        engine = nil
    }
}
