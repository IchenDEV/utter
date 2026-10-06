#if os(iOS)
import Foundation
import UtterRuntime
import UtterContracts
import UtterMediaContracts
import UtterAppleSpeech
import UtterData
import UtterWhisper
import UtterMLX

enum MobileError: Error { case microphoneDenied, localUnavailable, notEnabled, invalidInput, emptyResult }

@MainActor
final class MobileWorkflowFactory: SessionWorkflowFactory {
    let capture: any CaptureService
    let dictionary: any DictionaryService
    let preparation: any TextPreparationService
    var language = "zh"
    var modelID = "apple"
    var industry = "general"
    let lexicons: any LexiconService
    var maximumDuration = 120
    var sensitivity = "standard"
    let files: any ModelFilesService
    let access: any ModelResourceAccess

    init(capture: any CaptureService, dictionary: any DictionaryService, preparation: any TextPreparationService, files: any ModelFilesService, access: any ModelResourceAccess, lexicons: any LexiconService) {
        self.capture = capture; self.dictionary = dictionary; self.preparation = preparation
        self.files = files; self.access = access; self.lexicons = lexicons
    }

    func make(_ intent: SessionIntent) throws -> any SessionJob {
        guard intent.input == .local || { if case .text = intent.input { return true }; return false }() else { throw MobileError.invalidInput }
        let frozen = dictionary.snapshot(industryLexicon: lexicons.snapshot(for: IndustryLexiconID(rawValue: industry) ?? .general), bundleIdentifier: nil, languageCode: language)
        return MobileJob(input: intent.input, language: language, dictionary: frozen,
                         preparation: preparation, capture: capture, modelID: modelID,
                         files: FrozenModelFiles(modelID: modelID, using: files), access: access,
                         maximumDuration: maximumDuration, sensitivity: sensitivity)
    }
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {}
}

@MainActor
private final class MobileJob: SessionJob {
    let input: SessionInput
    let language: String
    let dictionary: PersonalDictionarySnapshot
    let preparation: any TextPreparationService
    let capture: any CaptureService
    let modelID: String
    let files: FrozenModelFiles
    let access: any ModelResourceAccess
    let maximumDuration: Int
    let sensitivity: String
    var speech: (any SpeechEngine)?
    var recording: (any OwnedRecording)?
    var timeout: Task<Void, Never>?
    var revoked = false

    init(input: SessionInput, language: String, dictionary: PersonalDictionarySnapshot,
         preparation: any TextPreparationService, capture: any CaptureService, modelID: String,
         files: FrozenModelFiles, access: any ModelResourceAccess, maximumDuration: Int, sensitivity: String) {
        self.input = input; self.language = language; self.dictionary = dictionary
        self.preparation = preparation; self.capture = capture
        self.modelID = modelID; self.files = files; self.access = access
        self.maximumDuration = maximumDuration; self.sensitivity = sensitivity
    }

    func run(control: any SessionJobControl) async throws -> SessionCompletion {
        let transcript: String
        var activity: AudioCaptureActivity?
        if case .text(let text) = input {
            control.update(phase: .recording, transcript: "")
            try await waitForStop(control)
            transcript = text
        } else {
            try check(control)
            var settings = SettingsValues()
            settings.audioGateSensitivity = AudioSensitivity(rawValue: sensitivity) ?? .standard
            recording = try await capture.begin(CaptureRequest(source: .local(deviceID: nil), thresholds: settings.audioActivityThresholds),
                                                callbacks: CaptureCallbacks(inputUnavailable: { control.cancel() }))
            try check(control)
            control.update(phase: .recording, transcript: "")
            try await waitForStop(control)
            let audio = try await recording!.finish()
            activity = audio.activity
            try check(control)
            control.update(phase: .transcribing, transcript: "")
            guard let url = audio.url else { throw MobileError.emptyResult }
            if modelID == "apple" {
                transcript = try await AppleSpeechAnalyzer.transcribe(audioURL: url,
                locale: Locale(identifier: language == "en" ? "en-US" : "zh-CN"),
                context: SpeechRecognitionContext(phrases: dictionary.recognitionPhrases),
                allowAssetInstallation: false, log: Log(service: MobileDiagnostics()))
            } else {
                guard files.isCurrent else { throw MobileError.localUnavailable }
                if let directory = files.installedSpeechModelURL(modelID) {
                    speech = QwenNativeASREngine(modelPath: directory.path, modelID: modelID, access: access, log: Log(service: MobileDiagnostics()))
                } else {
                    let engine = WhisperEngine(modelName: modelID, files: files, access: access, log: Log(service: MobileDiagnostics()))
                    speech = engine
                    try await engine.loadModel(progress: { _ in })
                }
                try check(control)
                speech?.configureRecognition(context: SpeechRecognitionContext(phrases: dictionary.recognitionPhrases))
                transcript = try await speech!.transcribe(audioURL: url, language: language)
            }
        }
        try check(control)
        control.update(phase: .processing, transcript: "")
        guard let cleaned = preparation.transcript(transcript, activity: activity, recognitionPhrases: dictionary.recognitionPhrases) else { throw MobileError.emptyResult }
        let text = dictionary.applyReplacements(to: cleaned)
        guard !text.isEmpty else { throw MobileError.emptyResult }
        return SessionCompletion(transcript: transcript, text: text, acceptance: .returnedText)
    }

    private func waitForStop(_ control: any SessionJobControl) async throws {
        timeout = Task {
            do {
                try await Task.sleep(for: .seconds(maximumDuration))
                if control.isCurrent { control.stop() }
            } catch {}
        }
        defer { timeout?.cancel() }
        try await control.waitForStop()
    }

    func revoke() { revoked = true; timeout?.cancel(); recording?.revoke(); speech?.cancelListening() }
    func close() async {
        timeout?.cancel(); await recording?.close(); recording = nil
        if let speech { await Task { await speech.shutdown() }.value }; speech = nil
    }
    private func check(_ control: any SessionJobControl) throws {
        try Task.checkCancellation()
        guard !revoked, control.isCurrent else { throw CancellationError() }
    }
}

struct MobileDiagnostics: DiagnosticsService {
    // Backend error descriptions can contain user data. Retain only a content-free event.
    func info(_ message: String) { SystemDiagnostics().info("[iOS] Speech backend event") }
    func sensitive(_ message: String) {}
    func error(_ message: String) { SystemDiagnostics().error("[iOS] Speech backend failure") }
}
#endif
