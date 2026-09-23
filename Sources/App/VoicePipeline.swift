import Foundation
import AppKit

@MainActor
final class VoicePipeline {
    let appState: AppState
    let soundPlayer = SoundPlayer()
    let audioCapture: AudioCaptureManager = {
        let capture = AudioCaptureManager()
        capture.remoteMicSource = .shared
        return capture
    }()
    let textInserter = TextInserter()
    let correctionCapture = CorrectionCaptureService()
    let textProcessor: TextProcessor
    let overlay = OverlayPanel()
    let ownership: InputSessionOwnership
    let engineProvider: SpeechEngineProvider
    var sessionLease: UUID?
    var sessionEngine: (any SpeechEngine)?
    var enginePreparationTask: Task<Void, Never>?
    var sessionSettings: VoiceInputSettings?
    var recordingLanguage: String?
    var recordingStreaming = false
    var screenOCRTask: Task<ScreenContextSnapshot, Never>?
    var screenOCRStartedAt: CFAbsoluteTime?
    var processingTask: Task<Void, Never>?
    var replacementTask: Task<Void, Never>?
    var hideOverlayTask: Task<Void, Never>?
    var formattingModelLifecycleTask: Task<EspressoGenerationOutcome?, Never>?
    var recordingTargetApp: NSRunningApplication?
    var formattingPreloadGeneration = 0
    /// Injectable engine used by tests to drive the real `start` await through a
    /// controlled model-load barrier. `nil` in production.
    var engineOverride: (any SpeechEngine)?
    /// Injectable capture used by tests to observe whether a recording began.
    var captureOverride: AudioCaptureManager?

    /// The capture the pipeline uses; tests inject a spy.
    var activeCapture: AudioCaptureManager { captureOverride ?? audioCapture }
    /// Test-only stand-in for a slow model load, awaited before the readiness
    /// check so a counterexample can release the key mid-start.
    var engineLoadBarrier: (() async -> Void)?
    /// Test-only observation point for whether the remote capture path is used.
    var remoteCaptureSpy: RemoteMicCaptureSpy?

    var currentEngine: (any SpeechEngine)? { engineOverride ?? sessionEngine }

    init(
        appState: AppState,
        textProcessor: TextProcessor = TextProcessor(),
        ownership: InputSessionOwnership? = nil,
        engineProvider: SpeechEngineProvider? = nil
    ) {
        self.appState = appState
        self.textProcessor = textProcessor
        self.ownership = ownership ?? InputSessionOwnership()
        self.engineProvider = engineProvider ?? SpeechEngineProvider()
    }

    func warmUp() async {
        let settings = appState.settings
        let catalog = ModelCatalog.shared
        catalog.refreshStatus(recheckingErrors: true)
        let llmStatus = catalog.llmModels.first(where: { $0.id == settings.llmModel })?.status
        let formattingModelID = settings.localLLMBackend == .espresso
            ? settings.espressoModelPath
            : settings.llmModel
        let formattingModelAvailable = settings.localLLMBackend == .espresso
            ? FileManager.default.fileExists(atPath: NSString(string: settings.espressoModelPath).expandingTildeInPath)
            : (llmStatus == .downloaded || llmStatus == .ready)
        let shouldLoadSpeech = StartupModelPreloadPolicy.shouldPreloadSpeechModel(
            enabled: settings.preloadSpeechModelOnLaunch,
            speechEngine: settings.speechEngine,
            modelDownloaded: catalog.isWhisperDownloaded(settings.whisperModel)
        )
        let shouldLoadFormatting = StartupModelPreloadPolicy.shouldPreloadFormattingModel(
            enabled: settings.preloadFormattingModelOnLaunch,
            useRemoteLLM: settings.useRemoteLLM,
            modelID: formattingModelID,
            modelDownloaded: formattingModelAvailable
        )

        if shouldLoadSpeech, let lease = try? ownership.acquire() {
            await ensureEngineLoaded(requestPermission: false)
            sessionEngine = nil
            ownership.release(lease)
        }

        if shouldLoadFormatting {
            let espressoOutcome = await enqueueFormattingModelPreload(
                showFailureInStatus: false
            ).value
            if espressoOutcome != nil {
                return
            }
        }

        if !ownership.isBusy { markReadyIfPossible() }
    }

    func stop(targetApp: NSRunningApplication? = nil) async {
        guard appState.isRecording else {
            if sessionLease != nil, processingTask == nil { cancel() }
            Log.info("[VoicePipeline] stop: not recording (\(appState.phase)), ignoring")
            return
        }

        let resolvedTargetApp = targetApp ?? recordingTargetApp
        recordingTargetApp = nil
        soundPlayer.playStop()
        activeCapture.stop()

        appState.phase = .transcribing
        appState.statusMessage = L("pipeline.transcribing")

        let language = recordingLanguage
        let audioURL = activeCapture.lastRecordingURL
        let audioActivity = activeCapture.lastActivity
        guard let settings = sessionSettings else { return }
        let inputMode = appState.activeInputMode

        guard let lease = sessionLease else { return }
        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.processingTask = nil
                self.releaseSession(lease)
            }
            await self.enginePreparationTask?.value
            guard !Task.isCancelled else { return }
            await TextProcessor.withEspressoOutcomeTracking {
                await self.processRecording(
                    audioURL: audioURL,
                    audioActivity: audioActivity,
                    language: language,
                    settings: settings,
                    inputMode: inputMode,
                    targetApp: resolvedTargetApp
                )
            }
        }
    }

    func cancel() {
        guard let lease = sessionLease else { return }
        ownership.cancel(lease)
        processingTask?.cancel()
        enginePreparationTask?.cancel()
        replacementTask?.cancel()
        currentEngine?.cancelListening()
        activeCapture.stop()
        cancelScreenContextCapture()
        recordingTargetApp = nil
        soundPlayer.playStop()
        let wasRecording = appState.isRecording
        appState.reset()
        overlay.hide()
        // Preparation/processing releases only after its suspended work returns.
        if wasRecording, processingTask == nil {
            processingTask = Task { @MainActor in
                await enginePreparationTask?.value
                processingTask = nil
                releaseSession(lease)
            }
        }
    }

    func releaseSession(_ lease: UUID) {
        guard sessionLease == lease else { return }
        activeCapture.cleanupLastRecording()
        sessionEngine = nil
        enginePreparationTask = nil
        sessionSettings = nil
        sessionLease = nil
        ownership.release(lease)
    }

    func clearInFlightWork() {
        processingTask?.cancel()
        processingTask = nil
        replacementTask?.cancel()
        replacementTask = nil
        cancelScreenContextCapture()
        hideOverlayTask?.cancel()
        hideOverlayTask = nil
    }
}

enum StartupModelPreloadPolicy {
    static func shouldPreloadSpeechModel(
        enabled: Bool,
        speechEngine: SpeechEngineType,
        modelDownloaded: Bool
    ) -> Bool {
        enabled && speechEngine == .whisper && modelDownloaded
    }

    static func shouldPreloadFormattingModel(
        enabled: Bool,
        useRemoteLLM: Bool,
        modelID: String,
        modelDownloaded: Bool
    ) -> Bool {
        enabled &&
            !useRemoteLLM &&
            modelDownloaded &&
            !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
