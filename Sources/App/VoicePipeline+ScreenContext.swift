import Foundation

@MainActor
extension VoicePipeline {
    func startScreenContextCaptureIfNeeded() {
        let snapshot = sessionSettings ?? VoiceInputSettings(settings: appState.settings)
        let needsScreenContext = VoicePipelinePolicy.shouldCaptureScreenContext(
            outputMode: snapshot.outputMode,
            useScreenContext: snapshot.useScreenContext
        )
        guard needsScreenContext else {
            cancelScreenContextCapture()
            return
        }

        screenOCRStartedAt = CFAbsoluteTimeGetCurrent()
        let mode = ScreenContextMode.effectiveCaptureMode(
            preference: snapshot.processing.screenContextMode,
            useRemoteLLM: snapshot.processing.useRemoteLLM
                || snapshot.processing.localLLMBackend == .espresso,
            modelID: snapshot.llmModel
        )
        screenOCRTask = Task.detached(priority: .utility) {
            await ScreenOCR.capture(mode: mode)
        }
    }

    func finishScreenContextCapture() async -> ScreenContextSnapshot {
        let context = await screenOCRTask?.value ?? .empty
        if let screenOCRStartedAt {
            let elapsed = CFAbsoluteTimeGetCurrent() - screenOCRStartedAt
            Log.info("[VoicePipeline] screen context stage finished in \(String(format: "%.2f", elapsed))s")
        }
        screenOCRTask = nil
        screenOCRStartedAt = nil
        return context
    }

    func cancelScreenContextCapture() {
        screenOCRTask?.cancel()
        screenOCRTask = nil
        screenOCRStartedAt = nil
    }
}
