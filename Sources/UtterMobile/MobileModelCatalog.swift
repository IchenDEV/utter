#if os(iOS)
import Foundation
import UtterContracts
import UtterModels
import UtterMLX

/// The phone shows the desktop catalog (Whisper, the MLX speech models and the MLX text models) with the
/// parts this device cannot hold marked as such, instead of a hand-picked subset.
extension MobileController {
    func updateModels(_ snapshot: ModelCatalogSnapshot) {
        var rows: [MobileModel] = []
        rows += snapshot.whisper.map { project($0, kind: .speech, engine: .whisper) }
        rows += snapshot.speech.map { project($0, kind: .speech, engine: .mlxSpeech) }
        rows += snapshot.text.map { project($0, kind: .polish, engine: .mlxText) }
        models = rows
    }

    private func project(_ entry: CatalogModelEntry, kind: MobileModel.Kind, engine: MobileModel.Engine) -> MobileModel {
        let state: MobileModel.State
        switch entry.status {
        case .downloading: state = .downloading
        case .compiling, .loading: state = .preparing
        case .downloaded, .ready: state = .downloaded
        case .error(let message) where message == L("model.download_paused"): state = .paused
        case .error(let message), .unavailable(let message): state = .failed(message)
        case .notDownloaded: state = .notDownloaded
        }
        let expected = Self.expectedBytes(entry.id, engine: engine)
        let fit = Self.fit(for: entry, expected: expected, engine: engine)
        let tier: MobileModel.Tier
        switch entry.tier {
        case .recommended: tier = .recommended
        case .standard: tier = .standard
        case .legacy: tier = .legacy
        }
        let name = engine == .whisper ? "Whisper " + entry.displayName : entry.displayName
        return MobileModel(id: entry.id, kind: kind, name: name, detail: entry.hint, family: entry.family?.rawValue,
                           tier: engine == .whisper && !entry.hint.isEmpty ? .recommended : tier, fit: fit,
                           bytes: entry.cacheSize > 0 ? entry.cacheSize : (expected ?? 0), progress: entry.downloadProgress,
                           progressDetail: entry.downloadDetail, state: state, engine: engine)
    }

    private static func expectedBytes(_ id: String, engine: MobileModel.Engine) -> Int64? {
        if engine != .whisper { return ModelCatalog.defaultDownloadEstimateBytes(for: id) }
        let megabytes: [(String, Int64)] = [("large-v3-turbo", 1_600), ("large-v3", 3_100), ("large-v2", 3_100),
                                            ("medium", 1_500), ("small", 480), ("base", 145), ("tiny", 78)]
        return megabytes.first { WhisperModelSelection.matches(id, variant: $0.0) }.map { $0.1 * 1_000_000 }
    }

    private static func fit(for entry: CatalogModelEntry, expected: Int64?, engine: MobileModel.Engine) -> MobileModel.Fit {
        let result = engine == .mlxText ? entry.compatibility
            : DeviceCapability.check(modelID: entry.id, downloadSizeBytes: expected)
        switch result {
        case .compatible: return .ok
        case .marginal(let message): return .marginal(message)
        case .incompatible(let message): return .blocked(message)
        }
    }

    func requireDownloadedModel() throws {
        guard models.contains(where: { $0.id == selectedModel && $0.kind == .speech && $0.downloaded }) else {
            throw MobileError.localUnavailable
        }
    }

    /// Choosing a model does not switch voice input off: the next dictation reads the choice when it starts.
    public func selectModel(_ id: String) async {
        guard !status.isBusy, modelMutation == nil, !clearing else { return }
        if id == "apple" {
            guard selectedModel != id else { return }
            if !appleReady { await prepareAppleModel() }
            guard appleReady else { return }
            selectedModel = id; UserDefaults.standard.set(id, forKey: "mobile.model")
            return
        }
        if id == "system" {
            polishModel = id; UserDefaults.standard.set(id, forKey: "mobile.polish.model")
            return
        }
        guard let model = models.first(where: { $0.id == id && $0.downloaded }) else { return }
        switch model.kind {
        case .speech: selectedModel = id; UserDefaults.standard.set(id, forKey: "mobile.model")
        case .polish:
            polishModel = id; UserDefaults.standard.set(id, forKey: "mobile.polish.model")
            polishService.unload()
        }
    }

    public func downloadModel(_ id: String) async {
        guard !clearing, modelMutation != id, let model = models.first(where: { $0.id == id }), model.canDownload,
              let catalog = try? runtime?.service(ModelServices.catalog) else { return }
        switch model.engine {
        case .whisper: await catalog.downloadWhisper(id)
        case .mlxSpeech: await catalog.downloadASR(id, onProgress: nil)
        case .mlxText: await catalog.downloadLLM(id)
        }
        // Without the system model, the first rewrite model that arrives is the one to use.
        if model.kind == .polish, polishModel == "system", !MobilePolisher.isAvailable,
           models.contains(where: { $0.id == id && $0.downloaded }) { await selectModel(id) }
    }

    public func cancelDownload(_ id: String) {
        guard let model = models.first(where: { $0.id == id }) else { return }
        let kind: ModelDownloadKind
        switch model.engine { case .whisper: kind = .whisper; case .mlxSpeech: kind = .asr; case .mlxText: kind = .llm }
        (try? runtime?.service(ModelServices.catalog))?.cancelDownload(id, kind: kind)
    }

    public func deleteModel(_ id: String) async {
        guard !status.isBusy, modelMutation == nil, let model = models.first(where: { $0.id == id }),
              let catalog = try? runtime?.service(ModelServices.catalog) else { return }
        modelMutation = id
        defer { modelMutation = nil }
        if selectedModel == id {
            selectedModel = "apple"
            UserDefaults.standard.set("apple", forKey: "mobile.model")
        }
        if polishModel == id {
            polishModel = "system"
            UserDefaults.standard.set("system", forKey: "mobile.polish.model")
        }
        polishService.unload()
        switch model.engine {
        case .whisper: await catalog.deleteWhisper(id)
        case .mlxSpeech: await catalog.deleteASR(id)
        case .mlxText: await catalog.deleteLLM(id)
        }
    }
}
#endif
