import Foundation
import AppKit

@MainActor
final class VoicePipeline {
    let appState: AppState
    let soundPlayer = SoundPlayer()
    let audioCapture = AudioCaptureManager()
    let textInserter = TextInserter()
    let correctionCapture = CorrectionCaptureService()
    let textProcessor = TextProcessor()
    let overlay = OverlayPanel()
    var whisperEngine: WhisperEngine?
    var appleSpeechEngine: AppleSpeechEngine?
    var volcSpeechEngine: VolcSpeechEngine?
    var qwenSpeechEngine: LocalASREngine?
    var mimoSpeechEngine: LocalASREngine?
    var screenOCRTask: Task<ScreenContextSnapshot, Never>?
    var screenOCRStartedAt: CFAbsoluteTime?
    var processingTask: Task<Void, Never>?
    var replacementTask: Task<Void, Never>?
    var hideOverlayTask: Task<Void, Never>?
    var recordingTargetApp: NSRunningApplication?

    var currentEngine: (any SpeechEngine)? {
        switch appState.settings.speechEngine {
        case .whisper: return whisperEngine
        case .apple: return appleSpeechEngine
        case .volc: return volcSpeechEngine
        case .qwen3: return qwenSpeechEngine
        case .mimo: return mimoSpeechEngine
        }
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func warmUp() async {
        let settings = appState.settings
        let catalog = ModelCatalog.shared
        catalog.refreshStatus(recheckingErrors: true)
        let llmStatus = catalog.llmModels.first(where: { $0.id == settings.llmModel })?.status
        let shouldLoadSpeech = StartupModelPreloadPolicy.shouldPreloadSpeechModel(
            enabled: settings.preloadSpeechModelOnLaunch,
            speechEngine: settings.speechEngine,
            modelDownloaded: catalog.isWhisperDownloaded(settings.whisperModel)
        )
        let shouldLoadFormatting = StartupModelPreloadPolicy.shouldPreloadFormattingModel(
            enabled: settings.preloadFormattingModelOnLaunch,
            useRemoteLLM: settings.useRemoteLLM,
            modelID: settings.llmModel,
            modelDownloaded: llmStatus == .downloaded || llmStatus == .ready
        )

        if shouldLoadSpeech {
            await ensureEngineLoaded(requestPermission: false)
        }

        if shouldLoadFormatting {
            await preloadFormattingModel(showFailureInStatus: false)
        }

        markReadyIfPossible()
    }

    // MARK: - Recording

    func start(
        mode: VoiceInputMode = .dictation,
        targetApp: NSRunningApplication? = nil
    ) async {
        if appState.isBusy {
            Log.info("[VoicePipeline] start: busy (\(appState.phase)), ignoring")
            showBusyHint()
            return
        }

        if appState.isDownloading { return }

        correctionCapture.finishCurrentSession()

        if !(currentEngine?.isReady ?? false) {
            await ensureEngineLoaded(requestPermission: true)
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
        currentEngine?.configureRecognition(
            context: SpeechRecognitionContext(
                dictionaryEntries: PersonalDictionary.shared.entries
            )
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

        let micStarted = audioCapture.start(
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

    func stop(targetApp: NSRunningApplication? = nil) async {
        guard appState.isRecording else {
            Log.info("[VoicePipeline] stop: not recording (\(appState.phase)), ignoring")
            return
        }

        let resolvedTargetApp = targetApp ?? recordingTargetApp
        recordingTargetApp = nil
        soundPlayer.playStop()
        audioCapture.stop()

        appState.phase = .transcribing
        appState.statusMessage = L("pipeline.transcribing")

        let language = appState.settings.inputLanguage.whisperCode
        let audioURL = audioCapture.lastRecordingURL
        let audioActivity = audioCapture.lastActivity
        let settings = appState.settings
        let inputMode = appState.activeInputMode

        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
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
