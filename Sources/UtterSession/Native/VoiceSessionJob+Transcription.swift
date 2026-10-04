import Foundation
import UtterContracts
import UtterMediaContracts

extension VoiceSessionJob {
    func transcription(control: any SessionJobControl) async throws -> String {
        if case .text(let text) = input {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw IntegrationError.noSpeechDetected }
            startScreenCapture()
            return trimmed
        }
        guard let speechFiles, let speechDescriptor, speechFiles.isCurrent else { throw IntegrationError.modelNotReady }
        let selected = try await dependencies.speech.create(id: settings.speech.providerID,
            request: SpeechProviderRequest(selection: settings.speech, modelFiles: speechFiles))
        engine = selected
        try check(control)
        try await selected.requestPermission()
        try check(control)
        selected.configureRecognition(context: SpeechRecognitionContext(phrases: speechDescriptor.recognitionVocabulary == .personal
            ? settings.dictionary.personalRecognitionPhrases : settings.dictionary.recognitionPhrases))
        startScreenCapture()
        let (starts, continuation) = AsyncStream<Result<Void, Error>>.makeStream(bufferingPolicy: .bufferingNewest(2))
        let task = Task {
            defer { continuation.finish() }
            do { return try await self.capture(using: selected, control: control, onStarted: { continuation.yield(.success(())) }) }
            catch { continuation.yield(.failure(error)); throw error }
        }
        captureTask = task
        for await started in starts { try started.get(); break }
        try check(control)
        await selected.prepare()
        try check(control)
        guard selected.isReady else { throw IntegrationError.modelNotReady }
        let audio = try await task.value
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
        guard let transcript = dependencies.preparation.transcript(raw, activity: audio.activity,
            recognitionPhrases: settings.dictionary.recognitionPhrases) else { throw IntegrationError.noSpeechDetected }
        return transcript
    }

    func processingText(_ transcript: String) -> String {
        if case .selectionEdit = mode { return target?.selectedText ?? "" }
        return transcript
    }
}
