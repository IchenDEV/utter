import UtterContracts
import Foundation
import WhisperKit

@MainActor
extension ModelCatalog {

    package func downloadWhisper(_ id: String) async {
        await awaitStartupCleanup()
        guard !closed, !Task.isCancelled else { return }
        await downloadTasks.run(key: ModelDownloadKey(kind: .whisper, modelID: id)) { [weak self] token in
            await self?.performWhisperDownload(id, token: token)
        }
    }

    /// Internal test seam: it replaces only the dependency call while still
    /// exercising the public ModelCatalog download entry point, generation
    /// setup, cancellation arbitration, and cleanup path.
    package typealias WhisperDownloadOverride = @MainActor (
        String,
        URL,
        @Sendable (Progress) -> Void
    ) async throws -> Bool

    package static var whisperDownloadOverride: WhisperDownloadOverride?

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

        let staging = storage.generationStaging(for: token)
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
            let progressCallback: @Sendable (Progress) -> Void = { [weak self, progressTasks] progress in
                let completedUnitCount = progress.completedUnitCount
                let totalUnitCount = progress.totalUnitCount
                let fractionCompleted = progress.fractionCompleted
                progressTasks.enqueue {
                    guard let self,
                          self.downloadTasks.isCurrent(key, token: token),
                          let i = self.whisperModels.firstIndex(where: { $0.id == id }) else { return }
                    let downloadedBytes = ModelStorage.directorySize(at: modelDir)
                    let info = tracker.update(
                        completedBytes: downloadedBytes > 0
                            ? downloadedBytes
                            : completedUnitCount,
                        totalBytes: totalUnitCount,
                        fraction: fractionCompleted
                    )
                    if signal.advanced(
                        completedBytes: max(downloadedBytes, completedUnitCount),
                        fraction: info.fraction
                    ) {
                        watchdog.noteProgress()
                    }
                    self.whisperModels[i].downloadProgress = info.fraction
                    self.whisperModels[i].downloadDetail = info.detailText
                }
            }
            let handledByOverride: Bool
            if let override = Self.whisperDownloadOverride {
                handledByOverride = try await override(id, staging.downloadBase, progressCallback)
            } else {
                handledByOverride = false
            }
            if !handledByOverride {
                _ = try await WhisperKit.download(
                    variant: id,
                    downloadBase: staging.downloadBase,
                    progressCallback: progressCallback
                )
            }
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
            let published: Bool
            do {
                published = try await publish([prepared], key: key, token: token)
            } catch {
                await ModelStorage.discardPreparedGenerationOffMainActor(prepared)
                throw error
            }
            await ModelStorage.discardPreparedGenerationOffMainActor(prepared)
            guard published, downloadTasks.isCurrent(key, token: token) else { return }
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
            log.error("[ModelCatalog] Whisper download failed: \(error.localizedDescription)")
            guard downloadTasks.isCurrent(key, token: token) else { return }
            whisperModels[idx].status = .error(ModelDownloadFailureMessage.userFacing(error))
            whisperModels[idx].cacheSize = whisperVariantSize(id)
            whisperModels[idx].downloadDetail = ""
        }
    }

    /// Removes a Whisper model. Serialized against any download for the same
    /// model so a transfer that is still winding down cannot write into the
    /// directory being deleted.
    package func deleteWhisper(_ id: String) async {
        guard !closed else { return }
        let requested = settings.snapshot
        let storage = ConfiguredModelStorage(settings: { requested })
        guard whisperModels.contains(where: { $0.id == id }) else { return }
        await downloadTasks.runExclusive(key: ModelDownloadKey(kind: .whisper, modelID: id)) { [weak self] _ in
            guard let self else { return }
            await self.removeFiles { self.removeWhisperFiles(id, storage: storage, requested: requested) }
        }
    }

    private func removeWhisperFiles(_ id: String, storage: ConfiguredModelStorage, requested: SettingsValues) {
        guard let idx = whisperModels.firstIndex(where: { $0.id == id }) else { return }
        if storage.localWhisperURL(id) != nil {
            guard settings.localWhisperModelPaths[id] == requested.localWhisperModelPaths[id] else { return }
            var paths = settings.localWhisperModelPaths
            paths.removeValue(forKey: id)
            settings.localWhisperModelPaths = paths
            whisperModels.remove(at: idx)
        } else {
            try? FileManager.default.removeItem(at: storage.whisperVariantDir(id))
            ModelDownloadRecovery.purgePartialArtifacts(kind: .whisper, modelID: id, storageRoot: storage.root)
            whisperModels[idx].status = .notDownloaded
            whisperModels[idx].cacheSize = 0
        }

        refreshStatus()
        if settings.modelStoragePath == requested.modelStoragePath, settings.whisperModel == id {
            settings.whisperModel =
                nextAvailableWhisper(excluding: id) ?? whisperModels.first?.id ?? ""
        }
    }

    package func nextAvailableWhisper(excluding id: String) -> String? {
        whisperModels.first {
            $0.id != id && ($0.status == .downloaded || $0.status == .ready)
        }?.id
    }

    package func whisperVariantDir(_ variant: String) -> URL {
        storage.localWhisperURL(variant) ?? storage.whisperVariantDir(variant)
    }

    package func whisperVariantSize(_ variant: String) -> Int64 {
        let dir = whisperVariantDir(variant)
        guard FileManager.default.fileExists(atPath: dir.path) else { return 0 }
        return ModelStorage.directorySize(at: dir)
    }

    package func isWhisperDownloaded(_ variant: String) -> Bool {
        ModelStorage.whisperModelIsComplete(at: whisperVariantDir(variant))
    }

    package func llmRepoDir(_ modelID: String) -> URL? {
        storage.llmRepoDir(modelID)
    }

    package func llmRepoIsComplete(_ modelID: String) -> Bool {
        guard let dir = llmRepoDir(modelID) else { return false }
        return ModelStorage.llmRepoIsComplete(at: dir)
    }

    package func llmRepoSize(_ modelID: String) -> Int64 {
        guard let dir = llmRepoDir(modelID) else { return 0 }
        return ModelStorage.directorySize(at: dir)
    }

    // MARK: - Download recovery

    /// A download starts with a token-scoped staging root. On retry, stale
    /// partial markers from a completed failed transfer are removed from the
    /// published/legacy cache layout, while a cancelled generation retains its
    /// own staging root until its dependency I/O returns.
}
