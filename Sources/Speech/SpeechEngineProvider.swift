import Foundation

@MainActor
final class SpeechEngineProvider {
    private var whisperEngine: WhisperEngine?
    private var appleSpeechEngine: AppleSpeechEngine?
    private var volcSpeechEngine: VolcSpeechEngine?
    private var qwenSpeechEngine: QwenNativeASREngine?

    func engine(settings: AppSettings, requestPermission: Bool = true) async -> (any SpeechEngine)? {
        await ensureEngineLoaded(settings: settings, requestPermission: requestPermission)
        return currentEngine(for: settings.speechEngine)
    }

    private func currentEngine(for type: SpeechEngineType) -> (any SpeechEngine)? {
        switch type {
        case .whisper: return whisperEngine
        case .apple: return appleSpeechEngine
        case .volc: return volcSpeechEngine
        case .qwen3: return qwenSpeechEngine
        case .mimo: return nil
        }
    }

    private func ensureEngineLoaded(settings: AppSettings, requestPermission: Bool) async {
        switch settings.speechEngine {
        case .whisper:
            await ensureWhisperLoaded(modelID: settings.whisperModel)
        case .apple:
            if appleSpeechEngine == nil {
                let locale = Locale(identifier: settings.inputLanguage.localeIdentifier)
                appleSpeechEngine = AppleSpeechEngine(locale: locale)
            }
            if requestPermission, !(appleSpeechEngine?.isReady ?? false) {
                appleSpeechEngine?.requestAccess()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        case .volc:
            volcSpeechEngine = VolcSpeechEngine(
                appKey: settings.volcAppKey,
                accessKey: settings.volcAccessKey,
                resourceId: settings.volcResourceId
            )
        case .qwen3:
            guard localASRIsAvailable(settings.qwenASRModel) else {
                qwenSpeechEngine = nil
                Log.info("[SpeechEngineProvider] Qwen ASR model requires manual download: \(settings.qwenASRModel)")
                return
            }
            let modelPath = ModelCatalog.shared.asrModelPath(for: settings.qwenASRModel)
            if qwenSpeechEngine?.usesModel(at: modelPath) == true { return }
            qwenSpeechEngine = QwenNativeASREngine(modelPath: modelPath)
        case .mimo:
            settings.speechEngine = .apple
            await ensureEngineLoaded(settings: settings, requestPermission: requestPermission)
        }
    }

    private func ensureWhisperLoaded(modelID: String) async {
        if let engine = whisperEngine, engine.isReady || engine.isLoading {
            return
        }

        let catalog = ModelCatalog.shared
        catalog.refreshStatus(recheckingErrors: true)
        let alreadyDownloaded = catalog.isWhisperDownloaded(modelID)
        guard alreadyDownloaded else {
            whisperEngine = nil
            Log.info("[SpeechEngineProvider] Whisper model requires manual download: \(modelID)")
            return
        }

        let engine = WhisperEngine(modelName: modelID)
        whisperEngine = engine
        catalog.updateWhisperStatus(modelID, status: .loading)
        do {
            try await engine.loadModel { progress in
                switch progress.stage {
                case .downloading:
                    if alreadyDownloaded {
                        catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                    } else {
                        catalog.updateWhisperStatus(
                            modelID,
                            status: .downloading,
                            detail: progress.detailText
                        )
                    }
                case .compiling:
                    catalog.updateWhisperStatus(modelID, status: .compiling, detail: L("model.loading"))
                case .loading:
                    catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                case .done:
                    break
                }
            }
            catalog.updateWhisperStatus(modelID, status: .ready)
        } catch {
            catalog.updateWhisperStatus(modelID, status: .error(error.localizedDescription))
            Log.error("[SpeechEngineProvider] Whisper load failed: \(error.localizedDescription)")
        }
    }

    private func localASRIsAvailable(_ modelID: String) -> Bool {
        ModelCatalog.shared.refreshASRStatus(recheckingErrors: true)
        guard let status = ModelCatalog.shared.asrModels.first(where: { $0.id == modelID })?.status else {
            return false
        }
        return status == .downloaded || status == .ready
    }
}
