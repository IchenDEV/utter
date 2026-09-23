import AVFoundation
import Foundation

@MainActor
final class InputSessionCoordinator {
    struct ActiveSession {
        let sessionID: UUID
        let clientID: String
        let engine: any SpeechEngine
        let languageCode: String?
        let mode: OutputMode
        let inputLanguage: InputLanguage
        let useScreenContext: Bool
        let streamingEnabled: Bool
        let screenContextTask: Task<ScreenContextSnapshot, Never>?
        let client: IntegrationClient?
        var snapshot: VoiceInputSettings? = nil
    }

    let service: OpenTypeService
    private let audioCapture: AudioCaptureManager
    let engineProvider: SpeechEngineProvider
    let textProcessor: TextProcessor
    let settings: AppSettings
    let ownership: InputSessionOwnership
    var lease: UUID?
    var owner: (sessionID: UUID, clientID: String)?
    var cancelOperation: (() -> Void)?
    var engineLoader: ((AppSettings) async -> (any SpeechEngine)?)?
    var activeSession: ActiveSession?
    var requestSettings: VoiceInputSettings?
    var pendingHistory: (() -> Void)?
    #if DEBUG
    var speechActivityOverrideForTesting: ((URL?) async -> Bool)?
    #endif

    var isBusy: Bool { lease != nil }

    init(
        service: OpenTypeService,
        audioCapture: AudioCaptureManager = AudioCaptureManager(),
        engineProvider: SpeechEngineProvider? = nil,
        textProcessor: TextProcessor = TextProcessor(),
        settings: AppSettings = .shared,
        ownership: InputSessionOwnership? = nil
    ) {
        self.service = service
        self.audioCapture = audioCapture
        self.engineProvider = engineProvider ?? SpeechEngineProvider()
        self.textProcessor = textProcessor
        self.settings = settings
        self.ownership = ownership ?? InputSessionOwnership()
    }

    func startRecording(sessionID: UUID, clientID: String) async throws {
        let session = try reserve(sessionID: sessionID, clientID: clientID)
        try await runOperation(keepRecording: true) {
            try await self.prepareRecording(session)
        }
    }

    private func prepareRecording(_ session: InputSession) async throws {
        guard let owner else { throw CancellationError() }
        let (sessionID, clientID) = owner
        let effective = effectiveSettings(for: session.request)
        guard let snapshot = requestSettings else { throw CancellationError() }
        let microphoneID = snapshot.microphoneID
        let thresholds = snapshot.audioActivityThresholds
        let engine = try await loadSpeechEngine()
        let vocabularySnapshot = snapshot.dictionary
        engine.configureRecognition(
            context: recognitionContext(engine: engine, snapshot: vocabularySnapshot)
        )

        if effective.streamingEnabled, engine.supportsStreaming {
            engine.startListening(language: effective.languageCode) { [weak service] partialText in
                Task { @MainActor in
                    let preview = TranscriptionSanitizer.previewText(
                        partialText,
                        inputLanguage: effective.inputLanguage
                    )
                    guard !preview.isEmpty else { return }
                    try? service?.emitTranscriptPartial(
                        sessionID: sessionID,
                        clientID: clientID,
                        text: preview
                    )
                }
            }
        }

        audioCapture.thresholds = thresholds

        let micStarted = audioCapture.start(
            deviceID: microphoneID,
            levelUpdate: { _ in },
            bufferUpdate: effective.streamingEnabled && engine.supportsStreaming ? { buffer in
                engine.appendAudioBuffer(buffer)
            } : nil
        )
        guard micStarted else {
            engine.cancelListening()
            audioCapture.stop()
            audioCapture.cleanupLastRecording()
            throw IntegrationError.permissionDenied
        }

        do {
            try await service.startRecording(sessionID: sessionID, clientID: clientID)
            try checkCurrent()
            activeSession = ActiveSession(
                sessionID: sessionID,
                clientID: clientID,
                engine: engine,
                languageCode: effective.languageCode,
                mode: effective.mode,
                inputLanguage: effective.inputLanguage,
                useScreenContext: effective.useScreenContext,
                streamingEnabled: effective.streamingEnabled && engine.supportsStreaming,
                screenContextTask: startScreenContextCaptureIfNeeded(
                    mode: effective.mode,
                    useScreenContext: effective.useScreenContext
                ),
                client: service.integrationClient(id: clientID),
                snapshot: snapshot
            )
        } catch {
            audioCapture.stop()
            audioCapture.cleanupLastRecording()
            engine.cancelListening()
            throw error
        }
    }

    func stopRecording(sessionID: UUID, clientID: String) async throws -> InputSessionResult {
        guard let active = activeSession,
              active.sessionID == sessionID,
              active.clientID == clientID else {
            throw IntegrationError.invalidSessionState
        }

        guard cancelOperation == nil else { throw IntegrationError.invalidSessionState }
        return try await runOperation {
            self.audioCapture.stop()
            try await self.service.beginProcessing(sessionID: sessionID, clientID: clientID)
            try self.checkCurrent()
            let result = try await self.processRecording(active)
            try self.checkCurrent()
            try self.commitOutput(result.text, sessionID: sessionID, clientID: clientID)
            guard let completed = try self.service.session(sessionID, clientID: clientID) else {
                throw IntegrationError.sessionNotFound
            }
            return InputSessionResult(session: completed, transcript: result.transcript, text: result.text)
        }
    }

    func cancel(sessionID: UUID, clientID: String) async throws {
        // Authorize before touching shared capture or model resources.
        try await service.cancel(sessionID: sessionID, clientID: clientID)
        guard try service.session(sessionID, clientID: clientID)?.state == .cancelled,
              owner?.sessionID == sessionID, owner?.clientID == clientID else { return }
        cancelOwnedWork()
    }

    func releaseActiveSessionForShutdown(clientID: String? = nil) {
        guard let owner, clientID == nil || owner.clientID == clientID else { return }
        cancelOwnedWork()
        Task { try? await service.cancel(sessionID: owner.sessionID, clientID: owner.clientID) }
    }

    private func processRecording(_ active: ActiveSession) async throws -> (transcript: String, text: String) {
        AudioCaptureDiagnostics.log(audioCapture.lastActivity)
        guard audioCapture.lastActivity.hasMeaningfulAudio else {
            throw IntegrationError.noSpeechDetected
        }
        guard await recordingContainsSpeech(audioCapture.lastRecordingURL) else {
            throw IntegrationError.noSpeechDetected
        }
        try checkCurrent()

        let raw: String
        if active.streamingEnabled {
            raw = try await active.engine.finishListening(
                audioURL: audioCapture.lastRecordingURL,
                language: active.languageCode
            )
        } else {
            raw = try await active.engine.transcribe(
                audioURL: audioCapture.lastRecordingURL,
                language: active.languageCode
            )
        }

        try checkCurrent()
        let transcript = try prepareTranscript(
            raw, audioActivity: audioCapture.lastActivity,
            dictionarySnapshot: active.snapshot?.dictionary
        )

        try service.emitTranscriptFinal(
            sessionID: active.sessionID,
            clientID: active.clientID,
            text: transcript
        )

        let text = try await outputText(for: transcript, active: active)
        return (transcript, text)
    }

    func finishCapture() {
        audioCapture.stop()
        audioCapture.cleanupLastRecording()
    }

    func prepareTranscript(
        _ raw: String,
        audioActivity: AudioCaptureActivity?,
        dictionarySnapshot: PersonalDictionarySnapshot? = nil
    ) throws -> String {
        let vocabulary = dictionarySnapshot ?? requestSettings?.dictionary
        guard let transcript = TranscriptionSanitizer.prepare(
            raw, audioActivity: audioActivity,
            recognitionPhrases: vocabulary?.recognitionPhrases ?? []
        ) else {
            throw IntegrationError.noSpeechDetected
        }
        return transcript
    }

    func effectiveSettings(
        for request: InputSessionRequest
    ) -> (mode: OutputMode, inputLanguage: InputLanguage, useScreenContext: Bool, streamingEnabled: Bool, languageCode: String?) {
        let snapshot = requestSettings ?? VoiceInputSettings(settings: settings)
        let inputLanguage = request.language ?? snapshot.inputLanguage
        return (
            mode: request.mode ?? snapshot.outputMode,
            inputLanguage: inputLanguage,
            useScreenContext: request.useScreenContext ?? snapshot.useScreenContext,
            streamingEnabled: snapshot.streamingEnabled,
            languageCode: inputLanguage.whisperCode
        )
    }

    func startScreenContextCaptureIfNeeded(
        mode: OutputMode,
        useScreenContext: Bool
    ) -> Task<ScreenContextSnapshot, Never>? {
        guard VoicePipelinePolicy.shouldCaptureScreenContext(
            outputMode: mode,
            useScreenContext: useScreenContext
        ) else {
            return nil
        }
        let options = requestSettings?.processing ?? TextProcessingOptions(settings: settings)
        let contextMode = ScreenContextMode.effectiveCaptureMode(
            preference: options.screenContextMode,
            useRemoteLLM: options.useRemoteLLM || options.localLLMBackend == .espresso,
            modelID: options.llmModel
        )
        return Task.detached(priority: .utility) {
            await ScreenOCR.capture(mode: contextMode)
        }
    }

}
