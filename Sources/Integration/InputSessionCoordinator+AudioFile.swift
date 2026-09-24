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
            if cleanup { try? FileManager.default.removeItem(at: audioURL) }
        }
        let session = try reserve(sessionID: sessionID, clientID: clientID)
        return try await runOperation {
            let effective = self.effectiveSettings(for: session.request)
            guard let snapshot = self.requestSettings else { throw CancellationError() }
            let vocabulary = snapshot.dictionary
            let engine = try await self.loadSpeechEngine()
            engine.configureRecognition(context: self.recognitionContext(engine: engine, snapshot: vocabulary))
            let active = ActiveSession(
                sessionID: sessionID, clientID: clientID, engine: engine,
                languageCode: effective.languageCode, mode: effective.mode,
                inputLanguage: effective.inputLanguage, useScreenContext: effective.useScreenContext,
                streamingEnabled: false,
                screenContextTask: self.startScreenContextCaptureIfNeeded(
                    mode: effective.mode, useScreenContext: effective.useScreenContext
                ),
                client: self.service.integrationClient(id: clientID),
                snapshot: snapshot
            )
            self.activeSession = active
            try self.service.emitAudioReceived(sessionID: sessionID, clientID: clientID)
            try await self.service.beginProcessing(sessionID: sessionID, clientID: clientID)
            try self.checkCurrent()
            guard await self.recordingContainsSpeech(audioURL) else {
                throw IntegrationError.noSpeechDetected
            }
            try self.checkCurrent()
            let raw = try await engine.transcribe(audioURL: audioURL, language: effective.languageCode)
            try self.checkCurrent()
            let transcript = try self.prepareTranscript(
                raw, audioActivity: nil, dictionarySnapshot: vocabulary
            )
            try self.service.emitTranscriptFinal(sessionID: sessionID, clientID: clientID, text: transcript)
            let text = try await self.outputText(for: transcript, active: active)
            try self.checkCurrent()
            try self.commitOutput(text, sessionID: sessionID, clientID: clientID)
            guard let completed = try self.service.session(sessionID, clientID: clientID) else {
                throw IntegrationError.sessionNotFound
            }
            return InputSessionResult(session: completed, transcript: transcript, text: text)
        }
    }
}
