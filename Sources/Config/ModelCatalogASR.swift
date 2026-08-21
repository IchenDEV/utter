import Foundation
import Hub

extension ModelCatalog {
    static var asrDownloadBase: URL { whisperDownloadBase }

    static var defaultASRModels: [
        (id: String, displayName: String, hint: String, provider: LocalASRConfiguration.Provider)
    ] {
        [
            (
                LocalASRConfiguration.qwen3DefaultModel,
                "Qwen3-ASR 0.6B",
                L("model.qwen3_asr_quality"),
                .qwen3
            ),
            (
                LocalASRConfiguration.mimoDefaultModel,
                "MiMo-V2.5-ASR",
                L("model.mimo_asr_quality"),
                .mimo
            ),
        ]
    }

    func asrModels(for provider: LocalASRConfiguration.Provider) -> [ModelEntry] {
        asrModels.filter { asrProvider(for: $0.id) == provider }
    }

    func asrProvider(for id: String) -> LocalASRConfiguration.Provider? {
        Self.defaultASRModels.first { $0.id == id }?.provider
    }

    func asrRuntimeAvailability(for id: String) -> LocalASRRuntimeAvailability {
        guard let provider = asrProvider(for: id) else { return .supported }
        return LocalASRRuntime.availability(for: provider)
    }

    func asrModelPath(for id: String) -> String {
        asrSingleRepoIsComplete(id) ? ModelStorage.asrRepoDir(id)?.path ?? "" : ""
    }

    func mimoTokenizerPath() -> String {
        let id = LocalASRConfiguration.mimoTokenizerModel
        return asrSingleRepoIsComplete(id) ? ModelStorage.asrRepoDir(id)?.path ?? "" : ""
    }

    func mimoRepositoryPath() -> String {
        let dir = ModelStorage.mimoASRRepositoryDir()
        return Self.mimoRepositoryIsReady(at: dir) ? dir.path : ""
    }

    func refreshASRStatus(recheckingErrors: Bool = false) {
        for i in asrModels.indices where !asrModels[i].status.isBusy {
            let id = asrModels[i].id
            let size = asrRepoSize(id)
            asrModels[i].cacheSize = size
            if case .unavailable(let message) = asrRuntimeAvailability(for: id) {
                asrModels[i].status = .unavailable(message)
                continue
            }
            if recheckingErrors || (asrModels[i].status != .ready && !asrModels[i].status.isError) {
                asrModels[i].status = asrRepoIsComplete(id)
                    ? .downloaded
                    : asrMissingStatus(for: id, size: size)
            }
        }
    }

    func downloadASR(_ id: String, onProgress: ((DownloadProgressInfo) -> Void)? = nil) async {
        guard ProductEdition.current.capabilities.modelDownloads else {
            if let index = asrModels.firstIndex(where: { $0.id == id }) {
                asrModels[index].status = .error(L("offline_bundle.downloads_disabled"))
            }
            return
        }
        await downloadTasks.run(key: ModelDownloadKey(kind: .asr, modelID: id)) { [weak self] in
            await self?.performASRDownload(id, onProgress: onProgress)
        }
    }

    private func performASRDownload(
        _ id: String,
        onProgress: ((DownloadProgressInfo) -> Void)?
    ) async {
        guard let idx = asrModels.firstIndex(where: { $0.id == id }), !asrModels[idx].status.isDownloading else { return }
        if case .unavailable(let message) = asrRuntimeAvailability(for: id) {
            asrModels[idx].status = .unavailable(message)
            return
        }

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
            let repos = asrRequiredRepoIDs(for: id)
            let api = HubApi(downloadBase: Self.asrDownloadBase)
            let startedAt = Date()
            let estimatedTotalBytes = estimatedASRDownloadBytes(id) ?? 0
            if !asrModelFilesAreComplete(id) {
                let tracker = DownloadProgressTracker(startDate: startedAt, initialBytes: asrRepoSize(id))
                for (repoIndex, repoID) in repos.enumerated() {
                    _ = try await api.snapshot(from: ModelStorage.hubModelRepo(repoID)) { [weak self] progress in
                        Task { @MainActor in
                            guard let self, let i = self.asrModels.firstIndex(where: { $0.id == id }) else { return }
                            let repositoryFraction =
                                (Double(repoIndex) + progress.fractionCompleted) / Double(repos.count)
                            let fraction = repositoryFraction * 0.9
                            let completedBytes = self.asrRepoSize(id)
                            let info = tracker.update(
                                completedBytes: completedBytes,
                                totalBytes: estimatedTotalBytes,
                                fraction: fraction
                            )
                            self.asrModels[i].downloadProgress = info.fraction
                            self.asrModels[i].downloadDetail = info.detailText
                            onProgress?(info)
                        }
                    }
                }
            }
            if asrProvider(for: id) == .qwen3 {
                asrModels[idx].downloadProgress = max(asrModels[idx].downloadProgress, 0.9)
                asrModels[idx].downloadDetail = L("model.asr_installing_runtime")
                _ = try await LocalASRRuntime.ensurePythonPath(
                    for: .qwen3,
                    preferredPath: AppSettings.shared.localASRPythonPath
                )
            }
            try Task.checkCancellation()
            if let i = asrModels.firstIndex(where: { $0.id == id }) {
                asrModels[i].status = asrRepoIsComplete(id) ? .downloaded : .error(L("model.asr_incomplete"))
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
        let provider = asrProvider(for: id)
        for repoID in asrRequiredRepoIDs(for: id) {
            try? FileManager.default.removeItem(at: ModelStorage.hubModelRepoDir(repoID))
        }
        if provider == .mimo {
            try? FileManager.default.removeItem(at: ModelStorage.mimoASRRepositoryDir())
        }
        if let provider {
            try? FileManager.default.removeItem(at: ModelStorage.localASRRuntimeDir(for: provider))
        }
        asrModels[idx].cacheSize = 0
        asrModels[idx].status = asrMissingStatus(for: id, size: 0)
        asrModels[idx].downloadDetail = ""

        let settings = AppSettings.shared
        if provider == .qwen3, settings.qwenASRModel == id {
            settings.qwenASRModel = nextAvailableASR(for: .qwen3, excluding: id) ?? id
        }
        if provider == .mimo, settings.mimoASRModel == id {
            settings.mimoASRModel = nextAvailableASR(for: .mimo, excluding: id) ?? id
        }
    }

    func nextAvailableASR(for provider: LocalASRConfiguration.Provider, excluding id: String) -> String? {
        asrModels.first {
            $0.id != id &&
            asrProvider(for: $0.id) == provider &&
            ($0.status == .downloaded || $0.status == .ready)
        }?.id
    }

    private func asrRequiredRepoIDs(for id: String) -> [String] {
        if asrProvider(for: id) == .mimo {
            return [id, LocalASRConfiguration.mimoTokenizerModel]
        }
        return [id]
    }

    private func asrRepoIsComplete(_ id: String) -> Bool {
        let hasFiles = asrModelFilesAreComplete(id)
        switch asrProvider(for: id) {
        case .qwen3:
            return hasFiles && LocalASRRuntime.isReady(for: .qwen3)
        case .mimo:
            return hasFiles &&
                Self.mimoRepositoryIsReady(at: ModelStorage.mimoASRRepositoryDir()) &&
                LocalASRRuntime.isReady(for: .mimo)
        case nil:
            return hasFiles
        }
    }

    private func asrModelFilesAreComplete(_ id: String) -> Bool {
        asrRequiredRepoIDs(for: id).allSatisfy { asrSingleRepoIsComplete($0) }
    }

    private func asrMissingStatus(for id: String, size: Int64) -> ModelStatus {
        if case .unavailable(let message) = asrRuntimeAvailability(for: id) {
            return .unavailable(message)
        }
        guard size > 0 else { return .notDownloaded }
        if asrModelFilesAreComplete(id), asrProvider(for: id) == .qwen3 {
            return .error(L("model.asr_runtime_missing"))
        }
        return .error(L("model.asr_incomplete"))
    }

    private func asrRepoSize(_ id: String) -> Int64 {
        let modelSize = asrRequiredRepoIDs(for: id).reduce(Int64(0)) { $0 + asrSingleRepoSize($1) }
        guard let provider = asrProvider(for: id) else { return modelSize }
        let runtimeSize = ModelStorage.directorySize(at: ModelStorage.localASRRuntimeDir(for: provider))
        let repositorySize = provider == .mimo
            ? ModelStorage.directorySize(at: ModelStorage.mimoASRRepositoryDir())
            : 0
        return modelSize + runtimeSize + repositorySize
    }

    private func asrSingleRepoIsComplete(_ id: String) -> Bool {
        Self.asrRepoContainsRequiredFiles(id, at: ModelStorage.asrRepoDir(id))
    }

    private func asrSingleRepoSize(_ id: String) -> Int64 {
        guard let dir = ModelStorage.asrRepoDir(id) else { return 0 }
        return ModelStorage.directorySize(at: dir)
    }

    static func asrRepoContainsRequiredFiles(_ id: String, at dir: URL?) -> Bool {
        guard let dir else { return false }
        if id == LocalASRConfiguration.qwen3DefaultModel {
            return ModelStorage.qwenASRModelIsComplete(at: dir)
        }
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
        case LocalASRConfiguration.qwen3DefaultModel:
            return [
                "config.json",
                "model.safetensors",
                "model.safetensors.index.json",
                "preprocessor_config.json",
                "tokenizer_config.json",
                "vocab.json",
            ]
        case LocalASRConfiguration.mimoDefaultModel:
            return [
                "config.json",
                "model.safetensors.index.json",
                "tokenizer.json",
                "model-00001-of-00007.safetensors",
                "model-00002-of-00007.safetensors",
                "model-00003-of-00007.safetensors",
                "model-00004-of-00007.safetensors",
                "model-00005-of-00007.safetensors",
                "model-00006-of-00007.safetensors",
                "model-00007-of-00007.safetensors",
            ]
        case LocalASRConfiguration.mimoTokenizerModel:
            return ["config.json", "model.safetensors"]
        default:
            return ["config.json"]
        }
    }

}
