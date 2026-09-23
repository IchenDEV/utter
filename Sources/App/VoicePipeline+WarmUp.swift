import Foundation

@MainActor
extension VoicePipeline {
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
}
