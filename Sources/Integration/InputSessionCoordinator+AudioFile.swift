import Foundation

@MainActor
extension InputSessionCoordinator {
    func processAudioFile(
        sessionID: UUID,
        clientID: String,
        audioURL: URL,
        cleanup: Bool
    ) async throws -> InputSessionResult {
        defer {
            if cleanup {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
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
        engine.configureRecognition(
            context: SpeechRecognitionContext(
                phrases: PersonalDictionary.shared.snapshot().recognitionPhrases
            )
        )

        do {
            try service.emitAudioReceived(sessionID: sessionID, clientID: clientID)
            try await service.beginProcessing(sessionID: sessionID, clientID: clientID)
            let transcript = try await transcribeAudioURL(
                audioURL,
                engine: engine,
                languageCode: effective.languageCode
            )
            try service.emitTranscriptFinal(sessionID: sessionID, clientID: clientID, text: transcript)
            let active = ActiveSession(
                sessionID: sessionID,
                clientID: clientID,
                engine: engine,
                languageCode: effective.languageCode,
                mode: effective.mode,
                inputLanguage: effective.inputLanguage,
                useScreenContext: effective.useScreenContext,
                streamingEnabled: false,
                screenContextTask: startScreenContextCaptureIfNeeded(
                    mode: effective.mode,
                    useScreenContext: effective.useScreenContext
                ),
                client: service.integrationClient(id: clientID)
            )
            let text = try await outputText(for: transcript, active: active)
            try await service.completeSession(sessionID: sessionID, clientID: clientID, finalText: text)
            guard let completed = try service.session(sessionID, clientID: clientID) else {
                throw IntegrationError.sessionNotFound
            }
            return InputSessionResult(session: completed, transcript: transcript, text: text)
        } catch let error as IntegrationError {
            try? await service.failSession(sessionID: sessionID, clientID: clientID, error: error)
            throw error
        } catch {
            Log.error("[InputSessionCoordinator] audio file processing failed: \(error.localizedDescription)")
            try? await service.failSession(sessionID: sessionID, clientID: clientID, error: .operationFailed)
            throw IntegrationError.operationFailed
        }
    }

    private func transcribeAudioURL(
        _ audioURL: URL,
        engine: any SpeechEngine,
        languageCode: String?
    ) async throws -> String {
        let raw = try await engine.transcribe(audioURL: audioURL, language: languageCode)
        return try prepareTranscript(raw, audioActivity: nil)
    }
}
