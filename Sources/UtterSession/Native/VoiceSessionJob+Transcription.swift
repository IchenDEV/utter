import Foundation
import UtterContracts
import UtterMediaContracts

extension VoiceSessionJob {
    func transcription(control: any SessionJobControl) async throws -> String {
        if case .text(let text) = input {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw IntegrationError.noSpeechDetected }
            return trimmed
        }
        guard let speechFiles, let speechDescriptor, speechFiles.isCurrent else { throw IntegrationError.modelNotReady }
        let preparation = control.beginStage(.preparation)
        let selected = try await dependencies.speech.create(id: settings.speech.providerID,
            request: SpeechProviderRequest(selection: settings.speech, modelFiles: speechFiles))
        engine = selected
        try check(control)
        try await selected.requestPermission()
        try check(control)
        selected.configureRecognition(context: SpeechRecognitionContext(phrases: speechDescriptor.recognitionVocabulary == .personal
            ? settings.dictionary.personalRecognitionPhrases : settings.dictionary.recognitionPhrases))
        startStreamingIfReady(using: selected, control: control)
        try check(control)
        await selected.prepare()
        control.endStage(preparation)
        try check(control)
        guard selected.isReady else { throw IntegrationError.modelNotReady }
        guard let captureTask else { throw IntegrationError.invalidSessionState }
        let audio = try await captureTask.value
        try check(control)
        control.update(phase: .transcribing, transcript: "")
        if let activity = audio.activity, !activity.hasMeaningfulAudio { throw IntegrationError.noSpeechDetected }
        guard try await dependencies.evidence.containsSpeech(at: audio.url) else { throw IntegrationError.noSpeechDetected }
        try check(control)
        let transcription = control.beginStage(.transcription)
        let raw: String
        if audio.streaming {
            raw = try await selected.finishListening(audioURL: audio.url, language: settings.inputLanguage.whisperCode)
        } else {
            raw = try await selected.transcribe(audioURL: audio.url, language: settings.inputLanguage.whisperCode)
        }
        control.endStage(transcription)
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
