import Foundation
import MLXLLM
import MLXLMCommon
import WhisperKit

@MainActor
extension ModelCatalog {
    static var whisperDownloadBase: URL { ModelStorage.huggingFaceBase }

    func downloadWhisper(_ id: String) async {
        guard ProductEdition.current.capabilities.modelDownloads else {
            updateWhisperStatus(id, status: .error(L("offline_bundle.downloads_disabled")))
            return
        }
        await downloadTasks.run(key: ModelDownloadKey(kind: .whisper, modelID: id)) { [weak self] in
            await self?.performWhisperDownload(id)
        }
    }

    private func performWhisperDownload(_ id: String) async {
        guard let idx = whisperModels.firstIndex(where: { $0.id == id }),
              !whisperModels[idx].status.isDownloading else { return }

        if isWhisperDownloaded(id) {
            whisperModels[idx].status = .downloaded
            whisperModels[idx].cacheSize = whisperVariantSize(id)
            whisperModels[idx].downloadDetail = ""
            return
        }

        whisperModels[idx].status = .downloading
        whisperModels[idx].downloadProgress = 0

        do {
            let modelDir = ModelStorage.whisperVariantDir(id)
            let tracker = DownloadProgressTracker(initialBytes: ModelStorage.directorySize(at: modelDir))
            _ = try await WhisperKit.download(
                variant: id,
                downloadBase: Self.whisperDownloadBase,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        guard let self,
                              let i = self.whisperModels.firstIndex(where: { $0.id == id }) else { return }
                        let downloadedBytes = ModelStorage.directorySize(at: modelDir)
                        let info = tracker.update(
                            completedBytes: downloadedBytes > 0
                                ? downloadedBytes
                                : progress.completedUnitCount,
                            totalBytes: progress.totalUnitCount,
                            fraction: progress.fractionCompleted
                        )
                        self.whisperModels[i].downloadProgress = info.fraction
                        self.whisperModels[i].downloadDetail = info.detailText
                    }
                }
            )
            try Task.checkCancellation()
            if let i = whisperModels.firstIndex(where: { $0.id == id }) {
                whisperModels[i].status = isWhisperDownloaded(id)
                    ? .downloaded
                    : .error(L("model.download_incomplete"))
                whisperModels[i].cacheSize = whisperVariantSize(id)
                whisperModels[i].downloadDetail = ""
            }
        } catch is CancellationError {
            if let i = whisperModels.firstIndex(where: { $0.id == id }) {
                whisperModels[i].status = .error(L("model.download_paused"))
                whisperModels[i].cacheSize = whisperVariantSize(id)
                whisperModels[i].downloadProgress = 0
                whisperModels[i].downloadDetail = ""
            }
        } catch {
            Log.error("[ModelCatalog] Whisper download failed: \(error.localizedDescription)")
            whisperModels[idx].status = .error(ModelDownloadFailureMessage.userFacing(error))
            whisperModels[idx].cacheSize = whisperVariantSize(id)
            whisperModels[idx].downloadDetail = ""
        }
    }

    func deleteWhisper(_ id: String) {
        guard let idx = whisperModels.firstIndex(where: { $0.id == id }) else { return }
        if ModelStorage.localWhisperURL(id) != nil {
            var paths = settings.localWhisperModelPaths
            paths.removeValue(forKey: id)
            settings.localWhisperModelPaths = paths
            whisperModels.remove(at: idx)
        } else {
            try? FileManager.default.removeItem(at: whisperVariantDir(id))
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
        guard ProductEdition.current.capabilities.modelDownloads else {
            updateLLMStatus(id, status: .error(L("offline_bundle.downloads_disabled")))
            return
        }
        await downloadTasks.run(key: ModelDownloadKey(kind: .llm, modelID: id)) { [weak self] in
            await self?.performLLMDownload(id)
        }
    }

    private func performLLMDownload(_ id: String) async {
        guard let idx = llmModels.firstIndex(where: { $0.id == id }),
              !llmModels[idx].status.isDownloading else { return }
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

        llmModels[idx].status = .downloading
        llmModels[idx].downloadProgress = 0

        do {
            let estimatedTotalBytes = estimatedLLMDownloadBytes(id) ?? 0
            let repoDir = ModelStorage.hubModelRepoDir(id)
            let tracker = DownloadProgressTracker(
                initialBytes: ModelStorage.directorySize(at: repoDir)
            )
            _ = try await LLMModelFactory.shared.loadContainer(
                from: MLXModelLoading.downloader,
                using: MLXModelLoading.tokenizerLoader,
                configuration: ModelConfiguration(id: id)
            ) { [weak self] progress in
                Task { @MainActor in
                    guard let self,
                          let i = self.llmModels.firstIndex(where: { $0.id == id }) else { return }
                    let info = tracker.update(
                        completedBytes: ModelStorage.directorySize(at: repoDir),
                        totalBytes: estimatedTotalBytes,
                        fraction: progress.fractionCompleted
                    )
                    self.llmModels[i].downloadProgress = info.fraction
                    self.llmModels[i].downloadDetail = info.detailText
                }
            }
            try Task.checkCancellation()
            if let i = llmModels.firstIndex(where: { $0.id == id }) {
                llmModels[i].status = llmRepoIsComplete(id)
                    ? .downloaded
                    : .error(L("model.download_incomplete"))
                llmModels[i].cacheSize = llmRepoSize(id)
                llmModels[i].downloadDetail = ""
            }
        } catch is CancellationError {
            if let i = llmModels.firstIndex(where: { $0.id == id }) {
                llmModels[i].status = .error(L("model.download_paused"))
                llmModels[i].cacheSize = llmRepoSize(id)
                llmModels[i].downloadProgress = 0
                llmModels[i].downloadDetail = ""
            }
        } catch {
            if let i = llmModels.firstIndex(where: { $0.id == id }) {
                Log.error("[ModelCatalog] LLM download failed: \(error.localizedDescription)")
                llmModels[i].status = .error(ModelDownloadFailureMessage.userFacing(error))
                llmModels[i].cacheSize = llmRepoSize(id)
                llmModels[i].downloadDetail = ""
            }
        }
    }

    func deleteLLM(_ id: String) {
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
}
