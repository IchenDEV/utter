import Foundation
import UtterContracts
import UtterMediaContracts

extension VoiceSessionJob {
    struct Audio {
        let url: URL?
        let activity: AudioCaptureActivity?
        let streaming: Bool
    }

    func startCapture(control: any SessionJobControl) async throws {
        try check(control)
        if case .text = input { startScreenCapture(); return }
        let (starts, continuation) = AsyncStream<Result<Void, Error>>.makeStream(bufferingPolicy: .bufferingNewest(2))
        captureTask = Task {
            defer { continuation.finish() }
            do { return try await self.capture(control: control, onStarted: { continuation.yield(.success(())) }) }
            catch { continuation.yield(.failure(error)); throw error }
        }
        for await started in starts { try started.get(); break }
        try check(control)
        startScreenCapture()
    }

    func capture(control: any SessionJobControl, onStarted: () -> Void) async throws -> Audio {
        if case .file(let url) = input {
            _ = try dependencies.audioFiles.inspect(url)
            onStarted()
            return Audio(url: url, activity: nil, streaming: false)
        }
        capturing = true
        defer { capturing = false }
        let source: CaptureSource
        switch input {
        case .local: source = .local(deviceID: settings.microphoneID)
        case .remote(let token): source = .remote(token: token)
        case .file: preconditionFailure("File input is handled before capture")
        case .unselected: throw IntegrationError.invalidSessionState
        case .text: throw IntegrationError.invalidSessionState
        }
        let callbackTasks = callbacks
        let streamingCapture = streamingCapture
        recording = try await dependencies.capture.begin(CaptureRequest(source: source, thresholds: settings.audioActivityThresholds, preferRemoteMic: settings.remoteMicEnabled),
            callbacks: CaptureCallbacks(level: { [weak self, weak control] level in
                callbackTasks.enqueue {
                    guard let self, let control, self.capturing, (try? self.check(control)) != nil else { return }
                    control.updateAudioLevel(level)
                }
            }, buffer: settings.streamingEnabled ? { [weak self, weak control] buffer in
                guard streamingCapture.receiveBuffer() else { return }
                callbackTasks.enqueue {
                    guard let self, let control, self.capturing, (try? self.check(control)) != nil else { return }
                    self.engine?.appendAudioBuffer(buffer)
                }
            } : nil, inputUnavailable: { [weak self, weak control] in
                callbackTasks.enqueue {
                    guard let self, let control, (try? self.check(control)) != nil else { return }
                    self.captureFailure = CaptureError.startFailed(.noUsableInput)
                    control.cancel()
                }
            }))
        try check(control)
        dependencies.sounds?.playStart()
        control.update(phase: .recording, transcript: "")
        onStarted()
        try await control.waitForStop()
        finishingCapture = true
        let tail = control.beginStage(.tail)
        try check(control)
        control.update(phase: .transcribing, transcript: "")
        guard let recording else { throw IntegrationError.invalidSessionState }
        let audio = try await recording.finish()
        await callbacks.drain()
        control.endStage(tail)
        capturing = false
        dependencies.sounds?.playStop()
        return Audio(url: audio.url, activity: audio.activity, streaming: streamingCapture.finish())
    }

    func startStreamingIfReady(using engine: any SpeechEngine, control: any SessionJobControl) {
        guard capturing, !finishingCapture, !control.isStopped,
              settings.streamingEnabled, engine.supportsStreaming, engine.isReady,
              streamingCapture.beginStreaming() else { return }
        let callbacks = callbacks
        engine.startListening(language: settings.inputLanguage.whisperCode) { [weak self, weak control] text in
            callbacks.enqueue {
                guard let self, let control, self.capturing, (try? self.check(control)) != nil else { return }
                control.update(phase: self.finishingCapture ? .transcribing : .recording,
                    transcript: self.dependencies.preparation.preview(text, language: self.settings.inputLanguage))
            }
        }
    }

    func startScreenCapture() {
        guard intent.clientID == nil || settings.useScreenContext else { return }
        let shouldCapture: Bool
        switch mode {
        case .formatting: shouldCapture = settings.useScreenContext
        case .command, .selectionEdit: shouldCapture = true
        case .direct, .translation: shouldCapture = false
        }
        guard shouldCapture else { return }
        guard let screen = dependencies.screen else {
            screenTask = Task { ScreenContextSnapshot(text: "", image: nil, status: .captureFailed) }
            return
        }
        let captureMode = ScreenContextMode.effectiveCaptureMode(preference: options.screenContextMode,
            useRemoteLLM: options.useRemoteLLM || options.localLLMBackend == .espresso, modelID: options.llmModel)
        screenTask = Task {
            do { return try await screen.capture(mode: captureMode) }
            catch { return ScreenContextSnapshot(text: "", image: nil, status: .captureFailed) }
        }
    }

    func contextWithScreen(_ screen: String) -> InputContext {
        InputContext(appName: context.appName, bundleIdentifier: context.bundleIdentifier, windowTitle: context.windowTitle,
            screenContext: screen, textBeforeSelection: context.textBeforeSelection, selectedText: context.selectedText,
            textAfterSelection: context.textAfterSelection, outputMode: context.outputMode,
            inputLanguage: context.inputLanguage, source: context.source)
    }
}
