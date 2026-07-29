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
        processingTask?.cancel()
        processingTask = nil
        replacementTask?.cancel()
        replacementTask = nil
        appState.clearPendingReplacement()
        if appState.phase == .processing {
            appState.phase = .idle
            appState.statusMessage = L("status.ready")
        }
        appState.llmModelReady = false
        Task { await textProcessor.unloadLLM() }
    }

    func unloadLocalASR() {
        qwenSpeechEngine = nil
        mimoSpeechEngine = nil
    }

    func loadLLM() {
        Task {
            await preloadFormattingModel(showFailureInStatus: true)
        }
    }

    func preloadFormattingModel(showFailureInStatus: Bool) async {
        guard !appState.settings.useRemoteLLM else {
            appState.llmModelReady = true
            return
        }

        let model = appState.settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }

        let catalog = ModelCatalog.shared
        catalog.refreshStatus()
        let modelStatus = catalog.llmModels.first(where: { $0.id == model })?.status
        let shouldShowDownload = !(modelStatus == .downloaded || modelStatus == .ready)
        if shouldShowDownload {
            appState.phase = .downloading
            appState.statusMessage = L("pipeline.downloading")
            appState.resetDownloadProgress()
            catalog.updateLLMStatus(model, status: .downloading)
        } else {
            appState.statusMessage = L("pipeline.loading_llm")
            catalog.updateLLMStatus(model, status: .loading, detail: L("model.loading"))
        }

        let estimatedDownloadBytes = catalog.estimatedLLMDownloadBytes(model)
        let loaded = await textProcessor.warmUpLLM(
            model: model,
            estimatedDownloadBytes: estimatedDownloadBytes
        ) { [weak self] info in
            guard shouldShowDownload else { return }
            Task { @MainActor in
                guard let self, self.appState.isDownloading else { return }
                self.appState.updateDownloadProgress(info)
                self.appState.statusMessage = L("pipeline.downloading") + " \(info.percentText)"
                if let index = catalog.llmModels.firstIndex(where: { $0.id == model }) {
                    catalog.llmModels[index].status = .downloading
                    catalog.llmModels[index].downloadProgress = info.fraction
                    catalog.llmModels[index].downloadDetail = info.detailText
                }
            }
        }
        let ready = await textProcessor.isLLMReady
        appState.llmModelReady = loaded && ready

        if appState.llmModelReady {
            if shouldShowDownload {
                appState.phase = .idle
                appState.resetDownloadProgress()
            }
            catalog.updateLLMStatus(model, status: .ready)
            Log.info("[VoicePipeline] LLM model loaded into memory, ready for instant inference")
            appState.statusMessage = L("status.ready")
        } else {
            if shouldShowDownload {
                appState.phase = .idle
                appState.resetDownloadProgress()
            }
            catalog.updateLLMStatus(model, status: .error(L("pipeline.model_load_failed")))
            Log.info("[VoicePipeline] LLM warmup failed, will retry on demand")
            appState.statusMessage = showFailureInStatus ? L("pipeline.model_load_failed") : L("status.ready")
        }
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
            if !LocalASRRuntime.isReady(for: .qwen3),
               !catalog.asrModelPath(for: settings.qwenASRModel).isEmpty {
                do {
                    _ = try await LocalASRRuntime.ensurePythonPath(
                        for: .qwen3,
                        preferredPath: settings.localASRPythonPath
                    )
                } catch {
                    Log.error("[VoicePipeline] Qwen ASR runtime migration failed: \(error.localizedDescription)")
                }
            }
            guard localASRIsAvailable(settings.qwenASRModel) else {
                qwenSpeechEngine = nil
                markSpeechModelDownloadRequired(showInStatus: requestPermission)
                return
            }
            let engine = LocalASREngine(configuration: LocalASRConfiguration(
                provider: .qwen3,
                pythonPath: settings.localASRPythonPath,
                modelPath: catalog.asrModelPath(for: settings.qwenASRModel),
                tokenizerPath: "",
                repoPath: ""
            ))
            qwenSpeechEngine = engine
            Task { await engine.prepare() }
        case .mimo:
            let settings = appState.settings
            let catalog = ModelCatalog.shared
            guard localASRIsAvailable(settings.mimoASRModel) else {
                mimoSpeechEngine = nil
                markSpeechModelDownloadRequired(showInStatus: requestPermission)
                return
            }
            let engine = LocalASREngine(configuration: LocalASRConfiguration(
                provider: .mimo,
                pythonPath: settings.localASRPythonPath,
                modelPath: catalog.asrModelPath(for: settings.mimoASRModel),
                tokenizerPath: catalog.mimoTokenizerPath(),
                repoPath: catalog.mimoRepositoryPath()
            ))
            mimoSpeechEngine = engine
            Task { await engine.prepare() }
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
        appState.phase = .downloading
        appState.statusMessage = L("pipeline.preparing_model")
        appState.resetDownloadProgress()
        catalog.updateWhisperStatus(modelID, status: .downloading)

        do {
            try await engine.loadModel { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.appState.downloadProgress = progress.fraction

                    switch progress.stage {
                    case .downloading:
                        if alreadyDownloaded {
                            self.appState.statusMessage = L("pipeline.loading_model")
                            self.appState.resetDownloadProgress()
                            self.appState.downloadProgress = progress.fraction
                            catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                        } else {
                            self.appState.updateDownloadProgress(progress.info)
                            self.appState.downloadProgress = progress.fraction
                            self.appState.statusMessage = L("pipeline.downloading") + " \(progress.info.percentText)"
                            catalog.updateWhisperStatus(
                                modelID,
                                status: .downloading,
                                detail: progress.detailText
                            )
                        }
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
