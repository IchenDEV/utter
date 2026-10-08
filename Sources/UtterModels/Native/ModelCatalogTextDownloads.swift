import Foundation
import UtterContracts

@MainActor
extension ModelCatalog {
    package func downloadLLM(_ id: String) async {
        await awaitStartupCleanup()
        guard !closed, !Task.isCancelled else { return }
        await downloadTasks.run(key: ModelDownloadKey(kind: .llm, modelID: id)) { [weak self] token in
            await self?.performLLMDownload(id, token: token)
        }
    }

    private func performLLMDownload(_ id: String, token: UUID) async {
        let key = ModelDownloadKey(kind: .llm, modelID: id)
        guard let idx = llmModels.firstIndex(where: { $0.id == id }),
              !llmModels[idx].status.isDownloading,
              downloadTasks.isCurrent(key, token: token) else { return }
        if storage.localLLMURL(id) != nil {
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

        let staging = storage.generationStaging(for: token)
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
            try await textDownloads.download(id, staging) { [weak self, progressTasks] progress in
                progressTasks.enqueue {
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
            let published: Bool
            do {
                published = try await publish([prepared], key: key, token: token)
            } catch {
                await ModelStorage.discardPreparedGenerationOffMainActor(prepared)
                throw error
            }
            await ModelStorage.discardPreparedGenerationOffMainActor(prepared)
            guard published, downloadTasks.isCurrent(key, token: token) else { return }
            // Resolve/download happened in staging. Load again from the
            // published directory so this path proves that removing the Hub
            // cache and generation root cannot strand a lazy model reader.
            try await textDownloads.validate(ModelStorage.hubModelRepoDir(id, downloadBase: staging.storageRoot))
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
                log.error("[ModelCatalog] LLM download failed: \(error.localizedDescription)")
                llmModels[i].status = .error(ModelDownloadFailureMessage.userFacing(error))
                llmModels[i].cacheSize = llmRepoSize(id)
                llmModels[i].downloadDetail = ""
            }
        }
    }

    /// Removes an LLM model. Serialized against any download for the same model.
    package func deleteLLM(_ id: String) async {
        guard !closed else { return }
        let requested = settings.snapshot
        let storage = ConfiguredModelStorage(settings: { requested })
        guard llmModels.contains(where: { $0.id == id }) else { return }
        await downloadTasks.runExclusive(key: ModelDownloadKey(kind: .llm, modelID: id)) { [weak self] _ in
            guard let self else { return }
            await self.removeFiles { self.removeLLMFiles(id, storage: storage, requested: requested) }
        }
    }

    private func removeLLMFiles(_ id: String, storage: ConfiguredModelStorage, requested: SettingsValues) {
        guard let idx = llmModels.firstIndex(where: { $0.id == id }) else { return }
        if storage.localLLMURL(id) != nil {
            guard settings.localLLMModelPaths[id] == requested.localLLMModelPaths[id] else { return }
            var paths = settings.localLLMModelPaths
            paths.removeValue(forKey: id)
            settings.localLLMModelPaths = paths
            llmModels.remove(at: idx)
        } else {
            if let dir = storage.llmRepoDir(id) {
                try? FileManager.default.removeItem(at: dir)
            }
            ModelDownloadRecovery.purgePartialArtifacts(kind: .llm, modelID: id, storageRoot: storage.root)
            llmModels[idx].status = .notDownloaded
            llmModels[idx].cacheSize = 0
        }

        refreshStatus()
        if settings.modelStoragePath == requested.modelStoragePath, settings.llmModel == id {
            settings.llmModel = nextAvailableLLM(excluding: id) ?? llmModels.first?.id ?? ""
        }
    }

    package func nextAvailableLLM(excluding id: String) -> String? {
        llmModels.first {
            $0.id != id && ($0.status == .downloaded || $0.status == .ready)
        }?.id
    }

}
