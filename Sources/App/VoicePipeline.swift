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
    var whisperEngine: WhisperEngine?
    var appleSpeechEngine: AppleSpeechEngine?
    var volcSpeechEngine: VolcSpeechEngine?
    var qwenSpeechEngine: QwenNativeASREngine?
    var mlxSTTEngine: MLXSTTEngine?
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

    var currentEngine: (any SpeechEngine)? {
        if let engineOverride { return engineOverride }
        switch appState.settings.speechEngine {
        case .whisper: return whisperEngine
        case .apple: return appleSpeechEngine
        case .volc: return volcSpeechEngine
        case .qwen3: return qwenSpeechEngine
        case .firered, .megaASR: return mlxSTTEngine
        }
    }

    init(appState: AppState, textProcessor: TextProcessor = TextProcessor()) {
        self.appState = appState
        self.textProcessor = textProcessor
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

        if shouldLoadSpeech {
            await ensureEngineLoaded(requestPermission: false)
        }

        if shouldLoadFormatting {
            let espressoOutcome = await enqueueFormattingModelPreload(
                showFailureInStatus: false
            ).value
            if espressoOutcome != nil {
                return
            }
        }

        markReadyIfPossible()
    }

    // MARK: - Recording

    func start(
        mode: VoiceInputMode = .dictation,
        targetApp: NSRunningApplication? = nil,
        remoteSessionToken: UInt64? = nil
    ) async {
        if appState.isBusy {
            Log.info("[VoicePipeline] start: busy (\(appState.phase)), ignoring")
            showBusyHint()
            return
        }

        if appState.isDownloading { return }

        correctionCapture.finishCurrentSession()

        if let engineLoadBarrier {
            await engineLoadBarrier()
        }

        if !(currentEngine?.isReady ?? false) {
            await ensureEngineLoaded(requestPermission: true)
        }

        // Model loading above can take a while. A remote voice-key session may
        // have been released meanwhile; never commit that start (and never fall
        // back to the system microphone for a key the user already let go).
        if let remoteSessionToken,
           !RemoteMicStartGuard.shouldCommit(
               remoteSessionToken: remoteSessionToken,
               isCancelled: Task.isCancelled,
               isSessionCurrent: XiaomiRemoteMicBridge.isSessionCurrent
           ) {
            Log.info("[VoicePipeline] start: remote session superseded before commit; aborting")
            currentEngine?.cancelListening()
            cancelScreenContextCapture()
            return
        }

        guard currentEngine?.isReady ?? false else {
            let message = appState.statusMessage == L("pipeline.speech_model_download_required")
                ? appState.statusMessage
                : L("pipeline.model_load_failed")
            showErrorHint(message)
            return
        }

        // Warm the engine while the user is still speaking (no-op if already warm).
        if let engine = currentEngine {
            Task { await engine.prepare() }
        }

        clearInFlightWork()

        appState.reset()
        appState.activeInputMode = mode
        appState.phase = .recording
        appState.statusMessage = mode.isTranslation
            ? L("pipeline.recording_translation")
            : L("pipeline.recording")
        recordingTargetApp = targetApp

        if mode.isTranslation {
            cancelScreenContextCapture()
        } else {
            startScreenContextCaptureIfNeeded()
        }

        soundPlayer.playStart()
        showOverlay()

        let micID = appState.settings.microphoneID
        let language = appState.settings.inputLanguage.whisperCode
        let streamingEnabled = appState.settings.enableStreamingRecognitionBeta
        let vocabularySnapshot = PersonalDictionary.shared.snapshot(
            settings: appState.settings
        )
        currentEngine?.configureRecognition(
            context: SpeechRecognitionContext(phrases: vocabularySnapshot.recognitionPhrases)
        )
        if streamingEnabled {
            currentEngine?.startListening(language: language) { [weak self] partialText in
                Task { @MainActor in
                    guard let self, self.appState.isRecording else { return }
                    self.appState.rawTranscription = TranscriptionSanitizer.previewText(
                        partialText,
                        inputLanguage: self.appState.settings.inputLanguage
                    )
                }
            }
        }

        if let remoteCaptureSpy {
            let token = remoteCaptureSpy.currentToken
            let startedSpy = token.map { remoteCaptureSpy.start(token: $0) } ?? false
            guard startedSpy else {
                currentEngine?.cancelListening()
                cancelScreenContextCapture()
                recordingTargetApp = nil
                appState.phase = .error(L("pipeline.mic_failed_permissions"))
                appState.statusMessage = L("pipeline.mic_unavailable")
                overlay.hide()
                return
            }
            commitRecording(mode: mode, targetApp: targetApp)
            return
        }

        activeCapture.thresholds = appState.settings.audioActivityThresholds

        let micStarted = activeCapture.start(
            deviceID: micID,
            levelUpdate: { [weak self] level in
                Task { @MainActor in
                    self?.appState.audioLevel = level
                }
            },
            bufferUpdate: { [weak self] buffer in
                guard streamingEnabled else { return }
                self?.currentEngine?.appendAudioBuffer(buffer)
            }
        )
        guard micStarted else {
            currentEngine?.cancelListening()
            cancelScreenContextCapture()
            recordingTargetApp = nil
            appState.phase = .error(L("pipeline.mic_failed_permissions"))
            appState.statusMessage = L("pipeline.mic_unavailable")
            overlay.hide()
            return
        }
    }

    /// Marks the pipeline as committed and recording. Extracted so the
    /// test-only capture seam and the real capture path share one commit point.
    private func commitRecording(mode: VoiceInputMode, targetApp: NSRunningApplication?) {
        appState.phase = .recording
        appState.statusMessage = mode.isTranslation
            ? L("pipeline.recording_translation")
            : L("pipeline.recording")
        recordingTargetApp = targetApp
    }

    func stop(targetApp: NSRunningApplication? = nil) async {
        guard appState.isRecording else {
            Log.info("[VoicePipeline] stop: not recording (\(appState.phase)), ignoring")
            return
        }

        let resolvedTargetApp = targetApp ?? recordingTargetApp
        recordingTargetApp = nil
        soundPlayer.playStop()
        activeCapture.stop()

        appState.phase = .transcribing
        appState.statusMessage = L("pipeline.transcribing")

        let language = appState.settings.inputLanguage.whisperCode
        let audioURL = activeCapture.lastRecordingURL
        let audioActivity = activeCapture.lastActivity
        let settings = appState.settings
        let inputMode = appState.activeInputMode

        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
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
        guard appState.isRecording else {
            Log.info("[VoicePipeline] cancel: not recording (\(appState.phase)), ignoring")
            return
        }

        Log.info("[VoicePipeline] recording cancelled by user")
        clearInFlightWork()
        currentEngine?.cancelListening()
        audioCapture.stop()
        audioCapture.cleanupLastRecording()
        recordingTargetApp = nil
        soundPlayer.playStop()
        appState.reset()
        overlay.hide()
    }

    private func clearInFlightWork() {
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
