import Foundation
import MLXLLM
import MLXLMCommon
import WhisperKit

@MainActor
extension ModelCatalog {
    static var whisperDownloadBase: URL { ModelStorage.huggingFaceBase }

    func downloadWhisper(_ id: String) async {
        await downloadTasks.run(key: ModelDownloadKey(kind: .whisper, modelID: id)) { [weak self] token in
            await self?.performWhisperDownload(id, token: token)
        }
    }

    private func performWhisperDownload(_ id: String, token: UUID) async {
        let key = ModelDownloadKey(kind: .whisper, modelID: id)
        guard let idx = whisperModels.firstIndex(where: { $0.id == id }),
              !whisperModels[idx].status.isDownloading,
              downloadTasks.isCurrent(key, token: token) else { return }

        if isWhisperDownloaded(id) {
            whisperModels[idx].status = .downloaded
            whisperModels[idx].cacheSize = whisperVariantSize(id)
            whisperModels[idx].downloadDetail = ""
            return
        }

        let staging = ModelStorage.generationStaging(for: token)
        defer { ModelStorage.removeGenerationStaging(staging) }
        prepareCacheForRetry(kind: .whisper, modelID: id, status: whisperModels[idx].status)

        whisperModels[idx].status = .downloading
        whisperModels[idx].downloadProgress = 0

        let watchdog = makeStallWatchdog(key: key, token: token, kind: .whisper, modelID: id)
        let signal = DownloadProgressSignal()

        do {
            try ModelStorage.prepareGeneration(staging)
            let modelDir = ModelStorage.whisperVariantDir(
                id,
                downloadBase: staging.downloadBase
            )
            let tracker = DownloadProgressTracker(initialBytes: ModelStorage.directorySize(at: modelDir))
            _ = try await WhisperKit.download(
                variant: id,
                downloadBase: staging.downloadBase,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        guard let self,
                              self.downloadTasks.isCurrent(key, token: token),
                              let i = self.whisperModels.firstIndex(where: { $0.id == id }) else { return }
                        let downloadedBytes = ModelStorage.directorySize(at: modelDir)
                        let info = tracker.update(
                            completedBytes: downloadedBytes > 0
                                ? downloadedBytes
                                : progress.completedUnitCount,
                            totalBytes: progress.totalUnitCount,
                            fraction: progress.fractionCompleted
                        )
                        if signal.advanced(
                            completedBytes: max(downloadedBytes, progress.completedUnitCount),
                            fraction: info.fraction
                        ) {
                            watchdog.noteProgress()
                        }
                        self.whisperModels[i].downloadProgress = info.fraction
                        self.whisperModels[i].downloadDetail = info.detailText
                    }
                }
            )
            watchdog.stop()
            try Task.checkCancellation()
            guard downloadTasks.isCurrent(key, token: token) else { return }
            guard ModelStorage.whisperModelIsComplete(at: modelDir) else {
                if let i = whisperModels.firstIndex(where: { $0.id == id }) {
                    whisperModels[i].status = .error(L("model.download_incomplete"))
                    whisperModels[i].cacheSize = whisperVariantSize(id)
                    whisperModels[i].downloadDetail = ""
                }
                return
            }
            let prepared = try await ModelStorage.prepareGenerationCommitOffMainActor(
                kind: .whisper,
                modelID: id,
                staging: staging
            )
            defer { ModelStorage.discardPreparedGeneration(prepared) }
            let published = try downloadTasks.publishIfCurrent(key, token: token) {
                try ModelStorage.publishPreparedGeneration(prepared)
            }
            guard published else { return }
            if let i = whisperModels.firstIndex(where: { $0.id == id }) {
                let complete = isWhisperDownloaded(id)
                whisperModels[i].status = complete ? .downloaded : .error(L("model.download_incomplete"))
                whisperModels[i].cacheSize = whisperVariantSize(id)
                whisperModels[i].downloadDetail = ""
            }
        } catch is CancellationError {
            watchdog.stop()
            guard downloadTasks.isCurrent(key, token: token) else { return }
            if let i = whisperModels.firstIndex(where: { $0.id == id }) {
                whisperModels[i].status = .error(L("model.download_paused"))
                whisperModels[i].cacheSize = whisperVariantSize(id)
                whisperModels[i].downloadProgress = 0
                whisperModels[i].downloadDetail = ""
            }
        } catch {
            watchdog.stop()
            Log.error("[ModelCatalog] Whisper download failed: \(error.localizedDescription)")
            guard downloadTasks.isCurrent(key, token: token) else { return }
            whisperModels[idx].status = .error(ModelDownloadFailureMessage.userFacing(error))
            whisperModels[idx].cacheSize = whisperVariantSize(id)
            whisperModels[idx].downloadDetail = ""
        }
    }

    /// Removes a Whisper model. Serialized against any download for the same
    /// model so a transfer that is still winding down cannot write into the
    /// directory being deleted.
    func deleteWhisper(_ id: String) async {
        guard whisperModels.contains(where: { $0.id == id }) else { return }
        await downloadTasks.runExclusive(key: ModelDownloadKey(kind: .whisper, modelID: id)) { [weak self] _ in
            guard let self else { return }
            self.removeWhisperFiles(id)
        }
    }

    private func removeWhisperFiles(_ id: String) {
        guard let idx = whisperModels.firstIndex(where: { $0.id == id }) else { return }
        if ModelStorage.localWhisperURL(id) != nil {
            var paths = settings.localWhisperModelPaths
            paths.removeValue(forKey: id)
            settings.localWhisperModelPaths = paths
            whisperModels.remove(at: idx)
        } else {
            try? FileManager.default.removeItem(at: whisperVariantDir(id))
            ModelDownloadRecovery.purgePartialArtifacts(kind: .whisper, modelID: id)
            whisperModels[idx].status = .notDownloaded
            whisperModels[idx].cacheSize = 0
        }

        if settings.whisperModel == id {
            settings.whisperModel =
                nextAvailableWhisper(excluding: id) ?? whisperModels.first?.id ?? ""
        }
    }

    func nextAvailableWhisper(excluding id: String) -> String? {
        whisperModels.first {
            $0.id != id && ($0.status == .downloaded || $0.status == .ready)
        }?.id
    }

    func downloadLLM(_ id: String) async {
        await downloadTasks.run(key: ModelDownloadKey(kind: .llm, modelID: id)) { [weak self] token in
            await self?.performLLMDownload(id, token: token)
        }
    }

    private func performLLMDownload(_ id: String, token: UUID) async {
        let key = ModelDownloadKey(kind: .llm, modelID: id)
        guard let idx = llmModels.firstIndex(where: { $0.id == id }),
              !llmModels[idx].status.isDownloading,
              downloadTasks.isCurrent(key, token: token) else { return }
        if ModelStorage.localLLMURL(id) != nil {
            llmModels[idx].status = llmRepoIsComplete(id)
                ? .downloaded
                : .error(L("model.local_missing"))
            llmModels[idx].cacheSize = llmRepoSize(id)
            return
        }
        if llmRepoIsComplete(id) {
            llmModels[idx].status = .downloaded
            llmModels[idx].cacheSize = llmRepoSize(id)
            llmModels[idx].downloadDetail = ""
            return
        }

        prepareCacheForRetry(kind: .llm, modelID: id, status: llmModels[idx].status)

        llmModels[idx].status = .downloading
        llmModels[idx].downloadProgress = 0

        let watchdog = makeStallWatchdog(key: key, token: token, kind: .llm, modelID: id)
        let signal = DownloadProgressSignal()

        let staging = ModelStorage.generationStaging(for: token)
        defer { ModelStorage.removeGenerationStaging(staging) }

        do {
            try ModelStorage.prepareGeneration(staging)
            let estimatedTotalBytes = estimatedLLMDownloadBytes(id) ?? 0
            let repoDir = ModelStorage.hubModelRepoDir(
                id,
                downloadBase: staging.downloadBase
            )
            let tracker = DownloadProgressTracker(
                initialBytes: ModelStorage.directorySize(at: repoDir)
            )
            _ = try await MLXLMCommon.resolve(
                configuration: ModelConfiguration(id: id),
                from: MLXModelLoading.downloader(for: staging),
                useLatest: false
            ) { [weak self] progress in
                Task { @MainActor in
                    guard let self,
                          self.downloadTasks.isCurrent(key, token: token),
                          let i = self.llmModels.firstIndex(where: { $0.id == id }) else { return }
                    let downloadedBytes = ModelStorage.directorySize(at: repoDir)
                    let info = tracker.update(
                        completedBytes: downloadedBytes,
                        totalBytes: estimatedTotalBytes,
                        fraction: progress.fractionCompleted
                    )
                    if signal.advanced(
                        completedBytes: max(downloadedBytes, progress.completedUnitCount),
                        fraction: info.fraction
                    ) {
                        watchdog.noteProgress()
                    }
                    self.llmModels[i].downloadProgress = info.fraction
                    self.llmModels[i].downloadDetail = info.detailText
                }
            }
            watchdog.stop()
            try Task.checkCancellation()
            guard downloadTasks.isCurrent(key, token: token) else { return }
            guard ModelStorage.llmRepoIsComplete(at: repoDir) else {
                if let i = llmModels.firstIndex(where: { $0.id == id }) {
                    llmModels[i].status = .error(L("model.download_incomplete"))
                    llmModels[i].cacheSize = llmRepoSize(id)
                    llmModels[i].downloadDetail = ""
                }
                return
            }
            let prepared = try await ModelStorage.prepareGenerationCommitOffMainActor(
                kind: .llm,
                modelID: id,
                staging: staging
            )
            defer { ModelStorage.discardPreparedGeneration(prepared) }
            let published = try downloadTasks.publishIfCurrent(key, token: token) {
                try ModelStorage.publishPreparedGeneration(prepared)
            }
            guard published else { return }
            // Resolve/download happened in staging. Load again from the
            // published directory so this path proves that removing the Hub
            // cache and generation root cannot strand a lazy model reader.
            _ = try await LLMModelFactory.shared.loadContainer(
                from: ModelStorage.hubModelRepoDir(id),
                using: MLXModelLoading.tokenizerLoader
            )
            guard downloadTasks.isCurrent(key, token: token) else { return }
            if let i = llmModels.firstIndex(where: { $0.id == id }) {
                let complete = llmRepoIsComplete(id)
                llmModels[i].status = complete ? .downloaded : .error(L("model.download_incomplete"))
                llmModels[i].cacheSize = llmRepoSize(id)
                llmModels[i].downloadDetail = ""
            }
        } catch is CancellationError {
            watchdog.stop()
            guard downloadTasks.isCurrent(key, token: token) else { return }
            if let i = llmModels.firstIndex(where: { $0.id == id }) {
                llmModels[i].status = .error(L("model.download_paused"))
                llmModels[i].cacheSize = llmRepoSize(id)
                llmModels[i].downloadProgress = 0
                llmModels[i].downloadDetail = ""
            }
        } catch {
            watchdog.stop()
            guard downloadTasks.isCurrent(key, token: token) else { return }
            if let i = llmModels.firstIndex(where: { $0.id == id }) {
                Log.error("[ModelCatalog] LLM download failed: \(error.localizedDescription)")
                llmModels[i].status = .error(ModelDownloadFailureMessage.userFacing(error))
                llmModels[i].cacheSize = llmRepoSize(id)
                llmModels[i].downloadDetail = ""
            }
        }
    }

    /// Removes an LLM model. Serialized against any download for the same model.
    func deleteLLM(_ id: String) async {
        guard llmModels.contains(where: { $0.id == id }) else { return }
        await downloadTasks.runExclusive(key: ModelDownloadKey(kind: .llm, modelID: id)) { [weak self] _ in
            guard let self else { return }
            self.removeLLMFiles(id)
        }
    }

    private func removeLLMFiles(_ id: String) {
        guard let idx = llmModels.firstIndex(where: { $0.id == id }) else { return }
        if ModelStorage.localLLMURL(id) != nil {
            var paths = settings.localLLMModelPaths
            paths.removeValue(forKey: id)
            settings.localLLMModelPaths = paths
            llmModels.remove(at: idx)
        } else {
            if let dir = llmRepoDir(id) {
                try? FileManager.default.removeItem(at: dir)
            }
            ModelDownloadRecovery.purgePartialArtifacts(kind: .llm, modelID: id)
            llmModels[idx].status = .notDownloaded
            llmModels[idx].cacheSize = 0
        }

        if settings.llmModel == id {
            settings.llmModel = nextAvailableLLM(excluding: id) ?? llmModels.first?.id ?? ""
        }
    }

    func nextAvailableLLM(excluding id: String) -> String? {
        llmModels.first {
            $0.id != id && ($0.status == .downloaded || $0.status == .ready)
        }?.id
    }

    func whisperVariantDir(_ variant: String) -> URL {
        ModelStorage.localWhisperURL(variant) ?? ModelStorage.whisperVariantDir(variant)
    }

    func whisperVariantSize(_ variant: String) -> Int64 {
        let dir = whisperVariantDir(variant)
        guard FileManager.default.fileExists(atPath: dir.path) else { return 0 }
        return ModelStorage.directorySize(at: dir)
    }

    func isWhisperDownloaded(_ variant: String) -> Bool {
        ModelStorage.whisperModelIsComplete(at: whisperVariantDir(variant))
    }

    func llmRepoDir(_ modelID: String) -> URL? {
        ModelStorage.llmRepoDir(modelID)
    }

    func llmRepoIsComplete(_ modelID: String) -> Bool {
        guard let dir = llmRepoDir(modelID) else { return false }
        return ModelStorage.llmRepoIsComplete(at: dir)
    }

    func llmRepoSize(_ modelID: String) -> Int64 {
        guard let dir = llmRepoDir(modelID) else { return 0 }
        return ModelStorage.directorySize(at: dir)
    }

    // MARK: - Download recovery

    /// A download starts with a token-scoped staging root. On retry, stale
    /// partial markers from a completed failed transfer are removed from the
    /// published/legacy cache layout, while a cancelled generation retains its
    /// own staging root until its dependency I/O returns.
    func prepareCacheForRetry(
        kind: ModelDownloadKind,
        modelID: String,
        status: ModelStatus
    ) {
        if status.isError {
            let purged = ModelDownloadRecovery.purgePartialArtifacts(kind: kind, modelID: modelID)
            if !purged.isEmpty {
                Log.info(
                    "[ModelCatalog] Cleared \(purged.removedFiles) stale download file(s) for \(modelID)"
                )
            }
        }
        ModelDownloadRecovery.ensureLiveArtifactRoots(kind: kind, modelID: modelID)
    }

    func makeStallWatchdog(
        key: ModelDownloadKey,
        token: UUID,
        kind: ModelDownloadKind,
        modelID: String
    ) -> DownloadStallWatchdog {
        let watchdog = DownloadStallWatchdog()
        watchdog.start { [weak self] in
            guard let self, self.downloadTasks.isCurrent(key, token: token) else { return }
            if self.cancelStalledDownload(modelID, kind: kind) {
                self.markStalled(kind: kind, modelID: modelID)
            }
        }
        return watchdog
    }

    func markStalled(kind: ModelDownloadKind, modelID: String) {
        switch kind {
        case .whisper:
            guard let i = whisperModels.firstIndex(where: { $0.id == modelID }) else { return }
            whisperModels[i].status = .error(L("model.download_failed_stalled"))
            whisperModels[i].downloadProgress = 0
            whisperModels[i].downloadDetail = ""
            whisperModels[i].cacheSize = whisperVariantSize(modelID)
        case .llm:
            guard let i = llmModels.firstIndex(where: { $0.id == modelID }) else { return }
            llmModels[i].status = .error(L("model.download_failed_stalled"))
            llmModels[i].downloadProgress = 0
            llmModels[i].downloadDetail = ""
            llmModels[i].cacheSize = llmRepoSize(modelID)
        case .asr:
            guard let i = asrModels.firstIndex(where: { $0.id == modelID }) else { return }
            asrModels[i].status = .error(L("model.download_failed_stalled"))
            asrModels[i].downloadProgress = 0
            asrModels[i].downloadDetail = ""
            asrModels[i].cacheSize = asrRepoSize(modelID)
        }
    }
}
