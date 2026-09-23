import Foundation

@MainActor
final class SpeechEngineProvider {
    private var cachedEngine: (any SpeechEngine)?
    private var cachedSelection: Selection?
    private(set) var failureMessage: String?

    /// Value identity prevents a settings change during an await from selecting another engine.
    struct Selection: Equatable {
        let type: SpeechEngineType
        let model: String
        let modelPath: String
        let locale: String
        let appKey: String
        let accessKey: String
        let resourceID: String

        @MainActor
        init(settings: AppSettings, inputLanguage: InputLanguage? = nil) {
            type = settings.speechEngine
            switch type {
            case .whisper: model = settings.whisperModel
            case .qwen3: model = settings.qwenASRModel
            default: model = type.asrModelID ?? ""
            }
            modelPath = type == .qwen3 ? ModelCatalog.shared.asrModelPath(for: model) : ""
            locale = type == .apple ? (inputLanguage ?? settings.inputLanguage).localeIdentifier : ""
            appKey = type == .volc ? settings.volcAppKey : ""
            accessKey = type == .volc ? settings.volcAccessKey : ""
            resourceID = type == .volc ? settings.volcResourceId : ""
        }
    }

    func discardCachedEngine() {
        // An in-flight session retains its own engine until it drains.
        cachedEngine = nil
        cachedSelection = nil
    }

    func engine(
        settings: AppSettings,
        requestPermission: Bool = true,
        selection requestedSelection: Selection? = nil,
        progress: @escaping (WhisperEngine.DownloadProgress) -> Void = { _ in }
    ) async -> (any SpeechEngine)? {
        let selection = requestedSelection ?? Selection(settings: settings)
        failureMessage = nil
        if cachedSelection == selection, let engine = cachedEngine, engine.isReady {
            return engine
        }
        let engine: any SpeechEngine
        switch selection.type {
        case .whisper:
            guard let loaded = await loadWhisper(selection.model, progress: progress) else { return nil }
            engine = loaded
        case .apple:
            let apple = cachedSelection == selection
                ? (cachedEngine as? AppleSpeechEngine) ?? AppleSpeechEngine(locale: Locale(identifier: selection.locale))
                : AppleSpeechEngine(locale: Locale(identifier: selection.locale))
            if requestPermission, !apple.isReady {
                apple.requestAccess()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            engine = apple
        case .volc:
            engine = VolcSpeechEngine(
                appKey: selection.appKey, accessKey: selection.accessKey, resourceId: selection.resourceID
            )
        case .qwen3:
            guard localASRIsAvailable(selection.model) else { return nil }
            engine = QwenNativeASREngine(
                modelPath: selection.modelPath, modelID: selection.model
            )
        case .firered, .megaASR:
            guard localASRIsAvailable(selection.model) else { return nil }
            engine = MLXSTTEngine(modelID: selection.model)
        }
        cachedEngine = engine
        cachedSelection = selection
        return engine
    }

    private func loadWhisper(
        _ modelID: String,
        progress: @escaping (WhisperEngine.DownloadProgress) -> Void
    ) async -> WhisperEngine? {
        let catalog = ModelCatalog.shared
        catalog.refreshStatus(recheckingErrors: true)
        guard catalog.isWhisperDownloaded(modelID) else {
            failureMessage = L("pipeline.speech_model_download_required")
            return nil
        }
        let engine = WhisperEngine(modelName: modelID)
        catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
        do {
            try await engine.loadModel { update in
                progress(update)
                switch update.stage {
                case .compiling:
                    catalog.updateWhisperStatus(modelID, status: .compiling, detail: L("model.loading"))
                case .loading, .downloading:
                    catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                case .done: break
                }
            }
            catalog.updateWhisperStatus(modelID, status: .ready)
            return engine
        } catch {
            catalog.updateWhisperStatus(modelID, status: .error(error.localizedDescription))
            failureMessage = L("pipeline.model_load_failed")
            Log.error("[SpeechEngineProvider] Whisper load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func localASRIsAvailable(_ modelID: String) -> Bool {
        ModelCatalog.shared.refreshASRStatus(recheckingErrors: true)
        let status = ModelCatalog.shared.asrModels.first(where: { $0.id == modelID })?.status
        guard status == .downloaded || status == .ready else {
            failureMessage = L("pipeline.speech_model_download_required")
            return false
        }
        return true
    }
}
