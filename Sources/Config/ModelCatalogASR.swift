import Foundation
import Hub

extension ModelCatalog {
    static var asrDownloadBase: URL { whisperDownloadBase }

    static var defaultASRModels: [(id: String, displayName: String, hint: String)] {
        [
            (
                QwenASRModel.defaultID,
                "Qwen3-ASR 1.7B",
                L("model.qwen3_asr_quality")
            )
        ]
    }

    func asrModels(for engine: SpeechEngineType) -> [ModelEntry] {
        switch engine {
        case .qwen3:
            return asrModels.filter { $0.id == QwenASRModel.defaultID }
        case .mimo:
            return []
        default:
            return []
        }
    }

    func asrModelPath(for id: String) -> String {
        asrRepoIsComplete(id) ? ModelStorage.asrRepoDir(id)?.path ?? "" : ""
    }

    func refreshASRStatus(recheckingErrors: Bool = false) {
        for i in asrModels.indices where !asrModels[i].status.isBusy {
            let id = asrModels[i].id
            let size = asrRepoSize(id)
            asrModels[i].cacheSize = size
            if recheckingErrors || (asrModels[i].status != .ready && !asrModels[i].status.isError) {
                asrModels[i].status = asrRepoIsComplete(id)
                    ? .downloaded
                    : asrMissingStatus(size: size)
            }
        }
    }

    func downloadASR(_ id: String, onProgress: ((DownloadProgressInfo) -> Void)? = nil) async {
        await downloadTasks.run(key: ModelDownloadKey(kind: .asr, modelID: id)) { [weak self] in
            await self?.performASRDownload(id, onProgress: onProgress)
        }
    }

    private func performASRDownload(
        _ id: String,
        onProgress: ((DownloadProgressInfo) -> Void)?
    ) async {
        guard let idx = asrModels.firstIndex(where: { $0.id == id }),
              !asrModels[idx].status.isDownloading else { return }

        if asrRepoIsComplete(id) {
            asrModels[idx].status = .downloaded
            asrModels[idx].cacheSize = asrRepoSize(id)
            asrModels[idx].downloadDetail = ""
            return
        }

        asrModels[idx].status = .downloading
        asrModels[idx].downloadProgress = 0
        asrModels[idx].downloadDetail = ""

        do {
            let api = HubApi(downloadBase: Self.asrDownloadBase)
            let tracker = DownloadProgressTracker(
                startDate: Date(),
                initialBytes: asrRepoSize(id)
            )
            let estimatedTotalBytes = estimatedASRDownloadBytes(id) ?? 0
            let repositories = asrRequiredRepoIDs(for: id)
            for (repositoryIndex, repositoryID) in repositories.enumerated() {
                _ = try await api.snapshot(from: ModelStorage.hubModelRepo(repositoryID)) { [weak self] progress in
                    Task { @MainActor in
                        guard let self,
                              let i = self.asrModels.firstIndex(where: { $0.id == id }) else { return }
                        let repositoryFraction =
                            (Double(repositoryIndex) + progress.fractionCompleted) / Double(repositories.count)
                        let info = tracker.update(
                            completedBytes: self.asrRepoSize(id),
                            totalBytes: estimatedTotalBytes,
                            fraction: repositoryFraction
                        )
                        self.asrModels[i].downloadProgress = info.fraction
                        self.asrModels[i].downloadDetail = info.detailText
                        onProgress?(info)
                    }
                }
            }
            try Task.checkCancellation()
            if let i = asrModels.firstIndex(where: { $0.id == id }) {
                asrModels[i].status = asrRepoIsComplete(id)
                    ? .downloaded
                    : .error(L("model.asr_incomplete"))
                asrModels[i].cacheSize = asrRepoSize(id)
                asrModels[i].downloadDetail = ""
            }
        } catch is CancellationError {
            if let i = asrModels.firstIndex(where: { $0.id == id }) {
                asrModels[i].status = .error(L("model.download_paused"))
                asrModels[i].cacheSize = asrRepoSize(id)
                asrModels[i].downloadProgress = 0
                asrModels[i].downloadDetail = ""
            }
        } catch {
            if let i = asrModels.firstIndex(where: { $0.id == id }) {
                Log.error("[ModelCatalog] ASR download failed: \(error.localizedDescription)")
                asrModels[i].status = .error(ModelDownloadFailureMessage.userFacing(error))
                asrModels[i].cacheSize = asrRepoSize(id)
                asrModels[i].downloadDetail = ""
            }
        }
    }

    func deleteASR(_ id: String) {
        guard let idx = asrModels.firstIndex(where: { $0.id == id }) else { return }
        for repositoryID in asrRequiredRepoIDs(for: id) {
            try? FileManager.default.removeItem(at: ModelStorage.hubModelRepoDir(repositoryID))
        }
        asrModels[idx].cacheSize = 0
        asrModels[idx].status = .notDownloaded
        asrModels[idx].downloadDetail = ""

        let settings = AppSettings.shared
        if id == QwenASRModel.defaultID, settings.qwenASRModel == id {
            settings.qwenASRModel = QwenASRModel.defaultID
        }
    }

    private func asrRepoIsComplete(_ id: String) -> Bool {
        asrRequiredRepoIDs(for: id).allSatisfy {
            Self.asrRepoContainsRequiredFiles($0, at: ModelStorage.asrRepoDir($0))
        }
    }

    private func asrMissingStatus(size: Int64) -> ModelStatus {
        size > 0 ? .error(L("model.asr_incomplete")) : .notDownloaded
    }

    private func asrRepoSize(_ id: String) -> Int64 {
        asrRequiredRepoIDs(for: id).reduce(0) { total, repositoryID in
            guard let directory = ModelStorage.asrRepoDir(repositoryID) else { return total }
            return total + ModelStorage.directorySize(at: directory)
        }
    }

    private func asrRequiredRepoIDs(for id: String) -> [String] {
        [id]
    }

    static func asrRepoContainsRequiredFiles(_ id: String, at dir: URL?) -> Bool {
        guard let dir else { return false }
        return asrRequiredFiles(for: id).allSatisfy { relativePath in
            let file = dir.appendingPathComponent(relativePath)
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { return false }
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0 > 0
        }
    }

    static func asrRequiredFiles(for id: String) -> [String] {
        switch id {
        case QwenASRModel.defaultID:
            return [
                "config.json",
                "model.safetensors",
                "model.safetensors.index.json",
                "preprocessor_config.json",
                "tokenizer_config.json",
                "vocab.json",
                "merges.txt",
            ]
        default:
            return ["config.json"]
        }
    }
}
