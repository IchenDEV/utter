import Foundation

@MainActor
extension VoicePipeline {
    func startScreenContextCaptureIfNeeded() {
        let needsScreenContext = VoicePipelinePolicy.shouldCaptureScreenContext(
            outputMode: appState.settings.outputMode,
            useScreenContext: appState.settings.useScreenContext
        )
        guard needsScreenContext else {
            cancelScreenContextCapture()
            return
        }

        screenOCRStartedAt = CFAbsoluteTimeGetCurrent()
        let mode = ScreenContextMode.effectiveCaptureMode(
            preference: appState.settings.screenContextMode,
            useRemoteLLM: appState.settings.useRemoteLLM
                || appState.settings.localLLMBackend == .espresso,
            modelID: appState.settings.llmModel
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
