#if os(iOS)
import Foundation
import UtterRuntime
import UtterContracts
import UtterMediaContracts
import UtterAppleSpeech
import UtterData
import UtterWhisper
import UtterMLX
import UtterKeyboardBridge

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
    var selectionRequest: MobileSelectionRequest?

    init(capture: any CaptureService, dictionary: any DictionaryService, preparation: any TextPreparationService, files: any ModelFilesService, access: any ModelResourceAccess, lexicons: any LexiconService) {
        self.capture = capture; self.dictionary = dictionary; self.preparation = preparation
        self.files = files; self.access = access; self.lexicons = lexicons
    }

    func make(_ intent: SessionIntent) throws -> any SessionJob {
        let selection = selectionRequest?.sessionID == intent.id ? selectionRequest : nil
        if case .selectionEdit = intent.mode { guard selection != nil else { throw MobileError.invalidInput } }
        if case .restoreSelectionEdit(let operationID) = intent.operation {
            guard let selection, case .restore(let restoration) = selection.operation,
                  restoration.operationID == operationID else { throw MobileError.invalidInput }
        } else {
            guard intent.operation == .input, intent.input == .local || { if case .text = intent.input { return true }; return false }() else { throw MobileError.invalidInput }
        }
        let frozen = dictionary.snapshot(industryLexicon: lexicons.snapshot(for: IndustryLexiconID(rawValue: industry) ?? .general), bundleIdentifier: nil, languageCode: language)
        return MobileJob(input: intent.input, language: language, dictionary: frozen,
                         preparation: preparation, capture: capture, modelID: modelID,
                         files: FrozenModelFiles(modelID: modelID, using: files), access: access,
                         maximumDuration: maximumDuration, sensitivity: sensitivity, selection: selection)
    }
    func settle(_ intent: SessionIntent, result: Result<SessionCompletion, Error>) {
        if selectionRequest?.sessionID == intent.id { selectionRequest = nil }
    }
}

@MainActor
final class MobileJob: SessionJob {
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
    var live: MobileLiveSpeech?
    var revoked = false
    let selection: MobileSelectionRequest?
    var selectionOutput: KeyboardSelectionOperation?
    var presentationMode: TextProcessingMode? { selection == nil ? nil : .selectionEdit(.custom(""), spokenCommand: "") }

    init(input: SessionInput, language: String, dictionary: PersonalDictionarySnapshot,
         preparation: any TextPreparationService, capture: any CaptureService, modelID: String,
         files: FrozenModelFiles, access: any ModelResourceAccess, maximumDuration: Int, sensitivity: String,
         selection: MobileSelectionRequest? = nil) {
        self.input = input; self.language = language; self.dictionary = dictionary
        self.preparation = preparation; self.capture = capture
        self.modelID = modelID; self.files = files; self.access = access
        self.maximumDuration = maximumDuration; self.sensitivity = sensitivity
        self.selection = selection
    }

    func run(control: any SessionJobControl) async throws -> SessionCompletion {
        if let selection, case .restore = selection.operation { return try await restoreSelection(control: control) }
        let transcript: String
        var activity: AudioCaptureActivity?
        if case .text(let text) = input {
            control.update(phase: .recording, transcript: "")
            #if DEBUG
            // Stands in for live recognition so the keyboard's streaming can be exercised without a microphone.
            let feeder = Task { @MainActor in
                for part in 1...4 {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled, control.isCurrent else { return }
                    control.update(phase: .recording, transcript: String(text.prefix(text.count * part / 4)))
                }
            }
            defer { feeder.cancel() }
            #endif
            try await waitForStop(control)
            transcript = text
        } else {
            try check(control)
            var settings = SettingsValues()
            settings.audioGateSensitivity = AudioSensitivity(rawValue: sensitivity) ?? .standard
            let sink = DraftSink(control: control, preparation: preparation, dictionary: dictionary)
            if modelID == "apple" {
                live = MobileLiveSpeech(locale: Locale(identifier: language == "en" ? "en-US" : "zh-CN"),
                                        context: SpeechRecognitionContext(phrases: dictionary.recognitionPhrases),
                                        onDraft: { sink.submit($0) })
            }
            let tap = live
            recording = try await capture.begin(CaptureRequest(source: .local(deviceID: nil), thresholds: settings.audioActivityThresholds),
                                                callbacks: CaptureCallbacks(buffer: tap.map { live in { live.append($0) } },
                                                                            inputUnavailable: { control.cancel() }))
            try check(control)
            control.update(phase: .recording, transcript: "")
            try await waitForStop(control)
            sink.phase = .transcribing
            let audio = try await recording!.finish()
            activity = audio.activity
            try check(control)
            control.update(phase: .transcribing, transcript: sink.latest)
            defer { sink.close() }
            guard let url = audio.url else { throw MobileError.emptyResult }
            if modelID == "apple" {
                if let streamed = await live?.finish() { transcript = streamed }
                else {
                    transcript = try await AppleSpeechAnalyzer.transcribe(audioURL: url,
                    locale: Locale(identifier: language == "en" ? "en-US" : "zh-CN"),
                    context: SpeechRecognitionContext(phrases: dictionary.recognitionPhrases),
                    allowAssetInstallation: false, log: Log(service: MobileDiagnostics()))
                }
            } else {
                guard files.isCurrent else { throw MobileError.localUnavailable }
                if let directory = files.installedSpeechModelURL(modelID) {
                    let log = Log(service: MobileDiagnostics())
                    if MLXModelArtifacts.qwen.contains(where: { $0.id == modelID }) {
                        speech = QwenNativeASREngine(modelPath: directory.path, modelID: modelID, access: access, log: log)
                    } else {
                        speech = MLXSTTEngine(modelID: modelID, files: files, access: access, log: log)
                    }
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
        control.update(phase: .processing, transcript: transcript)
        if selection != nil { return try await finishSelection(transcript, control: control) }
        guard let cleaned = preparation.transcript(transcript, activity: activity, recognitionPhrases: dictionary.recognitionPhrases) else { throw MobileError.emptyResult }
        let text = dictionary.applyReplacements(to: cleaned)
        guard !text.isEmpty else { throw MobileError.emptyResult }
        return SessionCompletion(transcript: transcript, text: text, acceptance: .returnedText)
    }

    private func waitForStop(_ control: any SessionJobControl) async throws {
        timeout = Task {
            do {
                try await Task.sleep(for: .seconds(maximumDuration))
                if control.isCurrent { control.finalizeCapture(reason: .durationLimit) }
            } catch {}
        }
        defer { timeout?.cancel() }
        try await control.waitForStop()
    }

    func revoke() { revoked = true; timeout?.cancel(); recording?.revoke(); speech?.cancelListening(); live?.cancel(); clearSelectionPayload() }
    func close() async {
        timeout?.cancel(); live?.cancel(); live = nil; await recording?.close(); recording = nil
        if let speech { await Task { await speech.shutdown() }.value }; speech = nil
        clearSelectionPayload()
    }
    func check(_ control: any SessionJobControl) throws {
        try Task.checkCancellation()
        guard !revoked, control.isCurrent else { throw CancellationError() }
    }
}

/// Carries live drafts from the recognizer's thread to the session, newest first: a late, older draft is dropped.
@MainActor
private final class DraftSink: @unchecked Sendable {
    private let control: any SessionJobControl
    private let preparation: any TextPreparationService
    private let dictionary: PersonalDictionarySnapshot
    private let lock = NSLock()
    private nonisolated(unsafe) var counter = 0
    private var applied = 0
    private(set) var latest = ""
    var phase = SessionExecutionPhase.recording
    private var open = true

    func close() { open = false }

    init(control: any SessionJobControl, preparation: any TextPreparationService, dictionary: PersonalDictionarySnapshot) {
        self.control = control; self.preparation = preparation; self.dictionary = dictionary
    }

    nonisolated func submit(_ draft: String) {
        lock.lock(); counter += 1; let number = counter; lock.unlock()
        Task { @MainActor in self.apply(draft, number: number) }
    }

    private func apply(_ draft: String, number: Int) {
        guard open, number > applied else { return }
        applied = number
        let shown = dictionary.applyReplacements(to: preparation.preview(draft, language: .auto))
        guard !shown.isEmpty else { return }
        latest = shown
        control.update(phase: phase, transcript: shown)
    }
}

struct MobileDiagnostics: DiagnosticsService {
    // Backend error descriptions can contain user data. Retain only a content-free event.
    func info(_ message: String) { SystemDiagnostics().info("[iOS] Speech backend event") }
    func sensitive(_ message: String) {}
    func error(_ message: String) { SystemDiagnostics().error("[iOS] Speech backend failure") }
}
#endif
