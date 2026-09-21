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
            ),
            (
                "mlx-community/FireRedASR2-AED-mlx",
                "FireRedASR2-AED",
                L("model.firered_asr")
            ),
            (
                "mlx-community/Mega-ASR-6bit",
                "Mega-ASR 6bit",
                L("model.mega_asr")
            ),
        ]
    }

    /// All ASR model IDs that use the generic MLX STT engine.
    static let mlxSTTModelIDs: Set<String> = [
        "mlx-community/FireRedASR2-AED-mlx",
        "mlx-community/Mega-ASR-6bit",
    ]

    func asrModels(for engine: SpeechEngineType) -> [ModelEntry] {
        switch engine {
        case .qwen3:
            return asrModels.filter { $0.id == QwenASRModel.defaultID }
        case .firered:
            return asrModels.filter { $0.id == "mlx-community/FireRedASR2-AED-mlx" }
        case .megaASR:
            return asrModels.filter { $0.id == "mlx-community/Mega-ASR-6bit" }
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
        await downloadTasks.run(key: ModelDownloadKey(kind: .asr, modelID: id)) { [weak self] token in
            await self?.performASRDownload(id, token: token, onProgress: onProgress)
        }
    }

    private func performASRDownload(
        _ id: String,
        token: UUID,
        onProgress: ((DownloadProgressInfo) -> Void)?
    ) async {
        let key = ModelDownloadKey(kind: .asr, modelID: id)
        guard let idx = asrModels.firstIndex(where: { $0.id == id }),
              !asrModels[idx].status.isDownloading,
              downloadTasks.isCurrent(key, token: token) else { return }

        if asrRepoIsComplete(id) {
            asrModels[idx].status = .downloaded
            asrModels[idx].cacheSize = asrRepoSize(id)
            asrModels[idx].downloadDetail = ""
            return
        }

        if asrModels[idx].status.isError {
            let purged = ModelDownloadRecovery.purgePartialArtifacts(kind: .asr, modelID: id)
            if !purged.isEmpty {
                Log.info("[ModelCatalog] Cleared \(purged.removedFiles) stale download file(s) for \(id)")
            }
        }

        asrModels[idx].status = .downloading
        asrModels[idx].downloadProgress = 0
        asrModels[idx].downloadDetail = ""

        let watchdog = makeStallWatchdog(key: key, token: token, kind: .asr, modelID: id)
        let signal = DownloadProgressSignal()

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
                              self.downloadTasks.isCurrent(key, token: token),
                              let i = self.asrModels.firstIndex(where: { $0.id == id }) else { return }
                        let repositoryFraction =
                            (Double(repositoryIndex) + progress.fractionCompleted) / Double(repositories.count)
                        let downloadedBytes = self.asrRepoSize(id)
                        let info = tracker.update(
                            completedBytes: downloadedBytes,
                            totalBytes: estimatedTotalBytes,
                            fraction: repositoryFraction
                        )
                        if signal.advanced(
                            completedBytes: max(downloadedBytes, progress.completedUnitCount),
                            fraction: info.fraction
                        ) {
                            watchdog.noteProgress()
                        }
                        self.asrModels[i].downloadProgress = info.fraction
                        self.asrModels[i].downloadDetail = info.detailText
                        onProgress?(info)
                    }
                }
            }
            watchdog.stop()
            try Task.checkCancellation()
            guard downloadTasks.isCurrent(key, token: token) else { return }
            if let i = asrModels.firstIndex(where: { $0.id == id }) {
                asrModels[i].status = asrRepoIsComplete(id)
                    ? .downloaded
                    : .error(L("model.asr_incomplete"))
                asrModels[i].cacheSize = asrRepoSize(id)
                asrModels[i].downloadDetail = ""
            }
        } catch is CancellationError {
            watchdog.stop()
            guard downloadTasks.isCurrent(key, token: token) else { return }
            if let i = asrModels.firstIndex(where: { $0.id == id }) {
                asrModels[i].status = .error(L("model.download_paused"))
                asrModels[i].cacheSize = asrRepoSize(id)
                asrModels[i].downloadProgress = 0
                asrModels[i].downloadDetail = ""
            }
        } catch {
            watchdog.stop()
            guard downloadTasks.isCurrent(key, token: token) else { return }
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
        ModelDownloadRecovery.purgePartialArtifacts(kind: .asr, modelID: id)
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

    func asrRepoSize(_ id: String) -> Int64 {
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

    nonisolated static func asrRequiredFiles(for id: String) -> [String] {
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
        case "mlx-community/FireRedASR2-AED-mlx":
            return [
                "config.json",
                "tokenizer.json",
            ]
        case "mlx-community/Mega-ASR-6bit":
            return [
                "config.json",
                "tokenizer_config.json",
            ]
        default:
            return ["config.json"]
        }
    }
}
