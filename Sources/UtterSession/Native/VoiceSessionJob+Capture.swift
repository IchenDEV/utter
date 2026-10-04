import Foundation
import UtterContracts
import UtterMediaContracts

extension VoiceSessionJob {
    struct Audio {
        let url: URL?
        let activity: AudioCaptureActivity?
        let streaming: Bool
    }

    func capture(using engine: any SpeechEngine, control: any SessionJobControl) async throws -> Audio {
        if case .file(let url) = intent.input {
            _ = try dependencies.audioFiles.inspect(url)
            return Audio(url: url, activity: nil, streaming: false)
        }
        let streaming = settings.streamingEnabled && engine.supportsStreaming
        if streaming {
            let callbacks = callbacks
            engine.startListening(language: settings.inputLanguage.whisperCode) { [weak self, weak control] text in
                callbacks.enqueue {
                    guard let self, let control, self.capturing, (try? self.check(control)) != nil else { return }
                    control.update(phase: .recording, transcript: self.dependencies.preparation.preview(text, language: self.settings.inputLanguage))
                }
            }
        }
        let source: CaptureSource
        switch intent.input {
        case .local: source = .local(deviceID: settings.microphoneID)
        case .remote(let token): source = .remote(token: token)
        case .file: preconditionFailure("File input is handled before capture")
        }
        let callbackTasks = callbacks
        recording = try await dependencies.capture.begin(CaptureRequest(source: source, thresholds: settings.audioActivityThresholds),
            callbacks: CaptureCallbacks(buffer: streaming ? { [weak self, weak control] buffer in
                callbackTasks.enqueue {
                    guard let self, let control, self.capturing, (try? self.check(control)) != nil else { return }
                    engine.appendAudioBuffer(buffer)
                }
            } : nil, inputUnavailable: { [weak control] in
                callbackTasks.enqueue { control?.cancel() }
            }))
        try check(control)
        capturing = true
        dependencies.sounds?.playStart()
        control.update(phase: .recording, transcript: "")
        defer { capturing = false }
        try await control.waitForStop()
        capturing = false
        try check(control)
        dependencies.sounds?.playStop()
        guard let recording else { throw IntegrationError.invalidSessionState }
        let audio = try await recording.finish()
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
