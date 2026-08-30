import Foundation

@MainActor
extension VoicePipeline {
    func unloadWhisper() {
        whisperEngine?.unload()
        whisperEngine = nil
        appState.whisperModelReady = false
        appState.statusMessage = L("pipeline.whisper_unloaded")
    }

    func unloadLLM() {
        formattingPreloadGeneration += 1
        processingTask?.cancel()
        processingTask = nil
        replacementTask?.cancel()
        replacementTask = nil
        appState.clearPendingReplacement()
        if appState.phase == .processing {
            appState.phase = .idle
            appState.statusMessage = L("status.ready")
        } else if appState.statusMessage == L("pipeline.loading_llm") {
            appState.statusMessage = L("status.ready")
        }
        appState.llmModelReady = false
        Task { await textProcessor.unloadLLM() }
    }

    func unloadLocalASR() {
        qwenSpeechEngine = nil
    }

    func loadLLM() {
        Task {
            await preloadFormattingModel(showFailureInStatus: true)
        }
    }

    func preloadFormattingModel(showFailureInStatus: Bool) async {
        formattingPreloadGeneration += 1
        let preloadGeneration = formattingPreloadGeneration
        guard !appState.settings.useRemoteLLM else {
            appState.llmModelReady = true
            return
        }

        let settings = appState.settings
        let backend = settings.localLLMBackend
        let model = settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let espressoPath = settings.espressoModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = backend == .espresso ? espressoPath : model
        guard !selectedModel.isEmpty else { return }

        let catalog = ModelCatalog.shared
        let modelIsAvailable: Bool
        if backend == .espresso {
            modelIsAvailable = FileManager.default.fileExists(
                atPath: NSString(string: espressoPath).expandingTildeInPath
            )
        } else {
            catalog.refreshStatus()
            let status = catalog.llmModels.first(where: { $0.id == model })?.status
            modelIsAvailable = status == .downloaded || status == .ready
        }
        guard modelIsAvailable else {
            let message = L("model.download_required")
            if backend == .mlx {
                catalog.updateLLMStatus(model, status: .error(message))
            }
            appState.statusMessage = showFailureInStatus ? message : L("status.ready")
            return
        }

        appState.statusMessage = L("pipeline.loading_llm")
        if backend == .mlx {
            catalog.updateLLMStatus(model, status: .loading, detail: L("model.loading"))
        }

        let warmup = await textProcessor.warmUpLLM(
            model: model,
            backend: backend,
            espressoModelPath: espressoPath
        )
        guard preloadGeneration == formattingPreloadGeneration,
              formattingSelectionMatches(backend: backend, model: model, espressoPath: espressoPath) else {
            return
        }
        let ready = warmup.loaded ? await textProcessor.isLLMReady(for: backend) : false
        guard preloadGeneration == formattingPreloadGeneration,
              formattingSelectionMatches(backend: backend, model: model, espressoPath: espressoPath) else {
            return
        }
        appState.llmModelReady = warmup.loaded && ready

        if appState.llmModelReady {
            if warmup.fallbackMessage != nil,
               !settings.useRemoteLLM,
               settings.localLLMBackend == .espresso {
                settings.localLLMBackend = .mlx
            }
            if backend == .mlx {
                catalog.updateLLMStatus(model, status: .ready)
            }
            Log.info("[VoicePipeline] LLM model loaded into memory, ready for instant inference")
            appState.statusMessage = showFailureInStatus
                ? (warmup.fallbackMessage ?? L("status.ready"))
                : L("status.ready")
        } else {
            if backend == .mlx {
                catalog.updateLLMStatus(model, status: .error(L("pipeline.model_load_failed")))
            }
            Log.info("[VoicePipeline] LLM warmup failed, will retry on demand")
            let message = backend == .espresso
                ? (warmup.errorMessage ?? L("error.espresso_runtime_failed"))
                : L("pipeline.model_load_failed")
            appState.statusMessage = showFailureInStatus ? message : L("status.ready")
        }
    }

    private func formattingSelectionMatches(
        backend: LocalLLMBackend,
        model: String,
        espressoPath: String
    ) -> Bool {
        let settings = appState.settings
        guard !settings.useRemoteLLM, settings.localLLMBackend == backend else { return false }
        switch backend {
        case .mlx:
            return settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines) == model
        case .espresso:
            return settings.espressoModelPath.trimmingCharacters(in: .whitespacesAndNewlines) == espressoPath
        }
    }

    func applyEspressoFallbackIfNeeded(settings: AppSettings) async -> String? {
        guard let message = await textProcessor.consumeEspressoFallbackMessage() else { return nil }
        if !settings.useRemoteLLM, settings.localLLMBackend == .espresso {
            settings.localLLMBackend = .mlx
        }
        return message
    }

    func ensureEngineLoaded(requestPermission: Bool = true) async {
        switch appState.settings.speechEngine {
        case .whisper:
            await ensureWhisperLoaded(showMissingModelError: requestPermission)
        case .apple:
            if appleSpeechEngine == nil {
                let locale = Locale(identifier: appState.settings.inputLanguage.localeIdentifier)
                appleSpeechEngine = AppleSpeechEngine(locale: locale)
            }
            if requestPermission, !(appleSpeechEngine?.isReady ?? false) {
                appleSpeechEngine?.requestAccess()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        case .volc:
            let settings = appState.settings
            volcSpeechEngine = VolcSpeechEngine(
                appKey: settings.volcAppKey,
                accessKey: settings.volcAccessKey,
                resourceId: settings.volcResourceId
            )
        case .qwen3:
            let settings = appState.settings
            let catalog = ModelCatalog.shared
            guard localASRIsAvailable(settings.qwenASRModel) else {
                qwenSpeechEngine = nil
                markSpeechModelDownloadRequired(showInStatus: requestPermission)
                return
            }
            let modelPath = catalog.asrModelPath(for: settings.qwenASRModel)
            if qwenSpeechEngine?.usesModel(at: modelPath) == true { return }
            let engine = QwenNativeASREngine(modelPath: modelPath)
            qwenSpeechEngine = engine
            Task { await engine.prepare() }
        case .mimo:
            appState.settings.speechEngine = .apple
            await ensureEngineLoaded(requestPermission: requestPermission)
        }
    }

    private func localASRIsAvailable(_ modelID: String) -> Bool {
        ModelCatalog.shared.refreshASRStatus(recheckingErrors: true)
        guard let status = ModelCatalog.shared.asrModels.first(where: { $0.id == modelID })?.status else {
            return false
        }
        return status == .downloaded || status == .ready
    }

    private func ensureWhisperLoaded(showMissingModelError: Bool) async {
        if let engine = whisperEngine {
            if engine.isReady || engine.isLoading { return }
        }

        let modelID = appState.settings.whisperModel
        let catalog = ModelCatalog.shared
        catalog.refreshStatus(recheckingErrors: true)

        let alreadyDownloaded = catalog.isWhisperDownloaded(modelID)
        guard alreadyDownloaded else {
            whisperEngine = nil
            appState.whisperModelReady = false
            markSpeechModelDownloadRequired(showInStatus: showMissingModelError)
            return
        }

        let engine = WhisperEngine(modelName: modelID)
        whisperEngine = engine
        appState.phase = .loadingModel
        appState.statusMessage = L("pipeline.preparing_model")
        appState.resetDownloadProgress()
        catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))

        do {
            try await engine.loadModel { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.appState.downloadProgress = progress.fraction

                    switch progress.stage {
                    case .downloading:
                        self.appState.statusMessage = L("pipeline.loading_model")
                        self.appState.resetDownloadProgress()
                        self.appState.downloadProgress = progress.fraction
                        catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                    case .compiling:
                        self.appState.statusMessage = L("pipeline.loading_model")
                        self.appState.resetDownloadProgress()
                        self.appState.downloadProgress = progress.fraction
                        catalog.updateWhisperStatus(modelID, status: .compiling, detail: L("model.loading"))
                    case .loading:
                        self.appState.statusMessage = L("pipeline.loading_model")
                        self.appState.resetDownloadProgress()
                        self.appState.downloadProgress = progress.fraction
                        catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                    case .done:
                        break
                    }
                }
            }

            appState.whisperModelReady = true
            appState.resetDownloadProgress()
            appState.phase = .idle
            appState.statusMessage = L("status.ready")
            catalog.updateWhisperStatus(modelID, status: .ready)
        } catch let error as WhisperError {
            appState.whisperModelReady = false
            appState.resetDownloadProgress()

            let message: String
            switch error {
            case .downloadFailed:
                message = L("pipeline.download_failed")
            case .compileFailed:
                message = L("pipeline.compile_failed")
            case .loadFailed:
                message = L("pipeline.load_failed")
            default:
                message = error.localizedDescription
            }
            appState.phase = .error(message)
            appState.statusMessage = message
            catalog.updateWhisperStatus(modelID, status: .error(message))
        } catch {
            appState.whisperModelReady = false
            appState.resetDownloadProgress()
            let message = L("pipeline.model_load_failed_prefix") + error.localizedDescription
            appState.phase = .error(message)
            appState.statusMessage = message
            catalog.updateWhisperStatus(modelID, status: .error(message))
        }
    }

    private func markSpeechModelDownloadRequired(showInStatus: Bool) {
        guard showInStatus else { return }
        appState.resetDownloadProgress()
        let message = L("pipeline.speech_model_download_required")
        appState.phase = .error(message)
        appState.statusMessage = message
    }
}
