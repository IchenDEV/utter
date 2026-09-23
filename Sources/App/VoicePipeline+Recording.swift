import AppKit
import Foundation

@MainActor
extension VoicePipeline {
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
        guard let lease = try? ownership.acquire() else {
            showBusyHint()
            return
        }
        sessionLease = lease
        var started = false
        defer { if !started { releaseSession(lease) } }
        let snapshot = VoiceInputSettings(
            settings: appState.settings, bundleIdentifier: targetApp?.bundleIdentifier
        )
        sessionSettings = snapshot
        recordingLanguage = snapshot.inputLanguage.whisperCode
        recordingStreaming = snapshot.streamingEnabled
        let microphoneID = snapshot.microphoneID
        let vocabularySnapshot = snapshot.dictionary

        correctionCapture.finishCurrentSession()

        if let engineLoadBarrier {
            await engineLoadBarrier()
        }

        if engineOverride == nil {
            await ensureEngineLoaded(requestPermission: true)
        }

        guard (try? ownership.check(lease)) != nil else { return }

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

        let language = recordingLanguage
        let streamingEnabled = recordingStreaming && (currentEngine?.supportsStreaming ?? false)
        recordingStreaming = streamingEnabled
        currentEngine?.configureRecognition(
            context: SpeechRecognitionContext(phrases: currentEngine is QwenNativeASREngine
                ? vocabularySnapshot.personalRecognitionPhrases
                : vocabularySnapshot.recognitionPhrases)
        )
        if streamingEnabled {
            currentEngine?.startListening(language: language) { [weak self] partialText in
                Task { @MainActor in
                    guard let self, self.appState.isRecording,
                          self.sessionLease == lease, (try? self.ownership.check(lease)) != nil else { return }
                    self.appState.rawTranscription = TranscriptionSanitizer.previewText(
                        partialText,
                        inputLanguage: snapshot.inputLanguage
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
            started = true
            return
        }

        activeCapture.thresholds = snapshot.audioActivityThresholds

        let micStarted = activeCapture.start(
            deviceID: microphoneID,
            levelUpdate: { [weak self] level in
                Task { @MainActor in
                    guard let self, self.sessionLease == lease, self.appState.isRecording else { return }
                    self.appState.audioLevel = level
                }
            },
            bufferUpdate: { [weak self] buffer in
                guard streamingEnabled, self?.sessionLease == lease else { return }
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
        commitRecording(mode: mode, targetApp: targetApp)
        started = true
    }

    /// Marks the pipeline as committed and recording. Extracted so the
    /// test-only capture seam and the real capture path share one commit point.
    private func commitRecording(mode: VoiceInputMode, targetApp: NSRunningApplication?) {
        appState.phase = .recording
        appState.statusMessage = mode.isTranslation
            ? L("pipeline.recording_translation")
            : L("pipeline.recording")
        recordingTargetApp = targetApp
        if let engine = currentEngine {
            enginePreparationTask = Task { await engine.prepare() }
        }
    }

}
