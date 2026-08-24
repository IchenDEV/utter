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
    }

    let service: OpenTypeService
    private let audioCapture: AudioCaptureManager
    let engineProvider: SpeechEngineProvider
    let textProcessor: TextProcessor
    let settings: AppSettings
    let isUserWorkflowBusy: @MainActor () -> Bool
    var activeSession: ActiveSession?

    var isBusy: Bool { activeSession != nil }

    init(
        service: OpenTypeService,
        audioCapture: AudioCaptureManager = AudioCaptureManager(),
        engineProvider: SpeechEngineProvider? = nil,
        textProcessor: TextProcessor = TextProcessor(),
        settings: AppSettings = .shared,
        isUserWorkflowBusy: @escaping @MainActor () -> Bool = { false }
    ) {
        self.service = service
        self.audioCapture = audioCapture
        self.engineProvider = engineProvider ?? SpeechEngineProvider()
        self.textProcessor = textProcessor
        self.settings = settings
        self.isUserWorkflowBusy = isUserWorkflowBusy
    }

    func startRecording(sessionID: UUID, clientID: String) async throws {
        guard activeSession == nil, !isUserWorkflowBusy() else {
            throw IntegrationError.busy
        }
        guard let session = try service.session(sessionID, clientID: clientID) else {
            throw IntegrationError.sessionNotFound
        }
        let effective = effectiveSettings(for: session.request)
        guard let engine = await engineProvider.engine(settings: settings), engine.isReady else {
            throw IntegrationError.modelNotReady
        }
        let vocabularySnapshot = PersonalDictionary.shared.snapshot(settings: settings)
        engine.configureRecognition(
            context: SpeechRecognitionContext(phrases: vocabularySnapshot.recognitionPhrases)
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

        let micStarted = audioCapture.start(
            deviceID: settings.microphoneID,
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
                client: service.integrationClient(id: clientID)
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

        audioCapture.stop()
        do {
            try await service.beginProcessing(sessionID: sessionID, clientID: clientID)
            let result = try await processRecording(active)
            try await service.completeSession(sessionID: sessionID, clientID: clientID, finalText: result.text)
            guard let completed = try service.session(sessionID, clientID: clientID) else {
                throw IntegrationError.sessionNotFound
            }
            activeSession = nil
            audioCapture.cleanupLastRecording()
            return InputSessionResult(session: completed, transcript: result.transcript, text: result.text)
        } catch let error as IntegrationError {
            await failActiveSession(active, error: error)
            throw error
        } catch {
            Log.error("[InputSessionCoordinator] stop failed: \(error.localizedDescription)")
            await failActiveSession(active, error: .operationFailed)
            throw IntegrationError.operationFailed
        }
    }

    func cancel(sessionID: UUID, clientID: String) async throws {
        if let active = activeSession, active.sessionID == sessionID, active.clientID == clientID {
            release(active)
        }
        try await service.cancel(sessionID: sessionID, clientID: clientID)
    }

    func releaseActiveSessionForShutdown() {
        guard let active = activeSession else { return }
        release(active)
    }

    private func processRecording(_ active: ActiveSession) async throws -> (transcript: String, text: String) {
        guard audioCapture.lastActivity.hasMeaningfulAudio else {
            throw IntegrationError.noSpeechDetected
        }

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

        let transcript = try prepareTranscript(raw, audioActivity: audioCapture.lastActivity)

        try service.emitTranscriptFinal(
            sessionID: active.sessionID,
            clientID: active.clientID,
            text: transcript
        )

        let text = try await outputText(for: transcript, active: active)
        return (transcript, text)
    }

    func prepareTranscript(_ raw: String, audioActivity: AudioCaptureActivity?) throws -> String {
        guard let transcript = TranscriptionSanitizer.prepare(raw, audioActivity: audioActivity) else {
            throw IntegrationError.noSpeechDetected
        }
        return transcript
    }

    private func failActiveSession(_ active: ActiveSession, error: IntegrationError) async {
        release(active)
        try? await service.failSession(sessionID: active.sessionID, clientID: active.clientID, error: error)
    }

    private func release(_ active: ActiveSession) {
        active.engine.cancelListening()
        active.screenContextTask?.cancel()
        audioCapture.stop()
        audioCapture.cleanupLastRecording()
        activeSession = nil
    }

    func effectiveSettings(
        for request: InputSessionRequest
    ) -> (mode: OutputMode, inputLanguage: InputLanguage, useScreenContext: Bool, streamingEnabled: Bool, languageCode: String?) {
        let inputLanguage = request.language ?? settings.inputLanguage
        return (
            mode: request.mode ?? settings.outputMode,
            inputLanguage: inputLanguage,
            useScreenContext: request.useScreenContext ?? settings.useScreenContext,
            streamingEnabled: true,
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
        let contextMode = ScreenContextMode.effectiveCaptureMode(
            preference: settings.screenContextMode,
            useRemoteLLM: settings.useRemoteLLM,
            modelID: settings.llmModel
        )
        return Task.detached(priority: .utility) {
            await ScreenOCR.capture(mode: contextMode)
        }
    }

}
