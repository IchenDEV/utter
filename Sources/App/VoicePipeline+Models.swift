import Foundation

@MainActor
extension VoicePipeline {
    func unloadWhisper() {
        engineProvider.discardCachedEngine()
        appState.whisperModelReady = false
        appState.statusMessage = L("pipeline.whisper_unloaded")
    }

    func unloadLocalASR() {
        engineProvider.discardCachedEngine()
    }

    @discardableResult
    func preloadFormattingModelNow(showFailureInStatus: Bool) async -> EspressoGenerationOutcome? {
        formattingPreloadGeneration += 1
        let preloadGeneration = formattingPreloadGeneration
        guard !appState.settings.useRemoteLLM else {
            appState.llmModelReady = true
            return nil
        }

        let settings = appState.settings
        let backend = settings.localLLMBackend
        let model = settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let espressoPath = settings.espressoModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = backend == .espresso ? espressoPath : model
        guard !selectedModel.isEmpty else { return nil }

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
            return nil
        }

        appState.statusMessage = L("pipeline.loading_llm")
        if backend == .mlx {
            catalog.updateLLMStatus(model, status: .loading, detail: L("model.loading"))
        }

        let warmup = await textProcessor.warmUpLLM(
            model: model,
            backend: backend,
            espressoModelPath: espressoPath,
            fallbackToMLXOnEspressoFailure: settings.fallbackToMLXOnEspressoFailure
        )
        guard !Task.isCancelled,
              preloadGeneration == formattingPreloadGeneration,
              formattingSelectionMatches(backend: backend, model: model, espressoPath: espressoPath) else {
            return nil
        }
        let ready = warmup.loaded ? await textProcessor.isLLMReady(for: backend) : false
        guard !Task.isCancelled,
              preloadGeneration == formattingPreloadGeneration,
              formattingSelectionMatches(backend: backend, model: model, espressoPath: espressoPath) else {
            return nil
        }
        appState.llmModelReady = warmup.loaded && ready

        if appState.llmModelReady {
            EspressoFallbackPolicy.selectMLXIfNeeded(
                after: warmup.espressoOutcome,
                settings: settings,
                expectedEspressoModelPath: espressoPath
            )
            if backend == .mlx {
                catalog.updateLLMStatus(model, status: .ready)
            }
            Log.info("[VoicePipeline] LLM model loaded into memory, ready for instant inference")
            appState.statusMessage = warmup.espressoOutcome?.message ?? L("status.ready")
            presentEspressoWarmupOutcomeIfNeeded(warmup.espressoOutcome)
            return warmup.espressoOutcome
        } else {
            if backend == .mlx {
                catalog.updateLLMStatus(model, status: .error(L("pipeline.model_load_failed")))
            }
            Log.info("[VoicePipeline] LLM warmup failed, will retry on demand")
            let message = backend == .espresso
                ? (warmup.errorMessage ?? L("error.espresso_runtime_failed"))
                : L("pipeline.model_load_failed")
            appState.statusMessage = warmup.espressoOutcome != nil || showFailureInStatus
                ? message
                : L("status.ready")
            presentEspressoWarmupOutcomeIfNeeded(warmup.espressoOutcome)
            return warmup.espressoOutcome
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

    func consumeEspressoOutcome(
        settings: AppSettings,
        expectedEspressoModelPath: String
    ) async -> EspressoGenerationOutcome? {
        let outcome = await textProcessor.consumeEspressoOutcome()
        guard !Task.isCancelled else { return nil }
        EspressoFallbackPolicy.selectMLXIfNeeded(
            after: outcome,
            settings: settings,
            expectedEspressoModelPath: expectedEspressoModelPath
        )
        return outcome
    }

    func ensureEngineLoaded(requestPermission: Bool = true) async {
        let settings = appState.settings
        let isWhisper = settings.speechEngine == .whisper
        let lease = sessionLease
        if isWhisper {
            appState.phase = .loadingModel
            appState.statusMessage = L("pipeline.preparing_model")
        }
        let engine = await engineProvider.engine(settings: settings, requestPermission: requestPermission, selection: sessionSettings?.speech) { [weak self] progress in
            Task { @MainActor in
                guard let self, self.sessionLease == lease, self.appState.phase == .loadingModel else { return }
                self.appState.downloadProgress = progress.fraction
                self.appState.statusMessage = L("pipeline.loading_model")
            }
        }
        if let lease, (try? ownership.check(lease)) == nil { return }
        sessionEngine = engine
        if isWhisper {
            appState.whisperModelReady = engine?.isReady ?? false
            appState.resetDownloadProgress()
            appState.phase = .idle
        }
        if engine == nil, requestPermission {
            let message = engineProvider.failureMessage ?? L("pipeline.model_load_failed")
            appState.phase = .error(message)
            appState.statusMessage = message
        }
    }
}
