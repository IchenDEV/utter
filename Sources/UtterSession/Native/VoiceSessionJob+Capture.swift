import Foundation
import UtterContracts
import UtterMediaContracts

extension VoiceSessionJob {
    struct Audio {
        let url: URL?
        let activity: AudioCaptureActivity?
        let streaming: Bool
    }

    func capture(using engine: any SpeechEngine, control: any SessionJobControl, onStarted: () -> Void) async throws -> Audio {
        if case .file(let url) = input {
            _ = try dependencies.audioFiles.inspect(url)
            onStarted()
            return Audio(url: url, activity: nil, streaming: false)
        }
        let streaming = settings.streamingEnabled && engine.supportsStreaming && engine.isReady
        capturing = true
        defer { capturing = false }
        if streaming {
            let callbacks = callbacks
            engine.startListening(language: settings.inputLanguage.whisperCode) { [weak self, weak control] text in
                callbacks.enqueue {
                    guard let self, let control, self.capturing, (try? self.check(control)) != nil else { return }
                    control.update(phase: self.finishingCapture ? .transcribing : .recording,
                        transcript: self.dependencies.preparation.preview(text, language: self.settings.inputLanguage))
                }
            }
        }
        let source: CaptureSource
        switch input {
        case .local: source = .local(deviceID: settings.microphoneID)
        case .remote(let token): source = .remote(token: token)
        case .file: preconditionFailure("File input is handled before capture")
        case .unselected: throw IntegrationError.invalidSessionState
        case .text: throw IntegrationError.invalidSessionState
        }
        let callbackTasks = callbacks
        recording = try await dependencies.capture.begin(CaptureRequest(source: source, thresholds: settings.audioActivityThresholds),
            callbacks: CaptureCallbacks(buffer: streaming ? { [weak self, weak control] buffer in
                callbackTasks.enqueue {
                    guard let self, let control, self.capturing, (try? self.check(control)) != nil else { return }
                    engine.appendAudioBuffer(buffer)
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
        try check(control)
        control.update(phase: .transcribing, transcript: "")
        guard let recording else { throw IntegrationError.invalidSessionState }
        let audio = try await recording.finish()
        await callbacks.drain()
        capturing = false
        dependencies.sounds?.playStop()
        return Audio(url: audio.url, activity: audio.activity, streaming: streaming)
    }

    func startScreenCapture() {
        guard let screen = dependencies.screen else { return }
        let shouldCapture: Bool
        switch mode {
        case .formatting: shouldCapture = settings.useScreenContext
        case .command, .selectionEdit: shouldCapture = true
        case .direct, .translation: shouldCapture = false
        }
        guard shouldCapture else { return }
        let captureMode = ScreenContextMode.effectiveCaptureMode(preference: options.screenContextMode,
            useRemoteLLM: options.useRemoteLLM || options.localLLMBackend == .espresso, modelID: options.llmModel)
        screenTask = Task {
            do { return try await screen.capture(mode: captureMode) }
            catch { return .empty }
        }
    }

    func contextWithScreen(_ screen: String) -> InputContext {
        InputContext(appName: context.appName, bundleIdentifier: context.bundleIdentifier, windowTitle: context.windowTitle,
            screenContext: screen, textBeforeSelection: context.textBeforeSelection, selectedText: context.selectedText,
            textAfterSelection: context.textAfterSelection, outputMode: context.outputMode,
            inputLanguage: context.inputLanguage, source: context.source)
    }
}
