#if os(iOS)
import Foundation
import UtterContracts
import UtterModels
import UtterAppleSpeech

public struct MobileModel: Identifiable {
    public let id: String
    public let name: String
    public let detail: String
    public let bytes: Int64
    public let progress: Double
    public let downloading: Bool
    public let downloaded: Bool
    public let error: String?
    public let experimental: Bool
}

extension MobileController {
    public var libraryReady: Bool { runtime?.state == .ready }
    public var canChangeConfiguration: Bool { !status.isBusy && activation == nil && !disabling && !clearing && !applePreparing && modelMutation == nil }
    public var industryLexicon: String {
        get { UserDefaults.standard.string(forKey: "mobile.industry") ?? "general" }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "mobile.industry") }
    }
    public var recordingLimit: Int {
        get { let value = UserDefaults.standard.integer(forKey: "mobile.limit"); return [30, 60, 120].contains(value) ? value : 120 }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "mobile.limit") }
    }
    public var audioSensitivity: String {
        get { UserDefaults.standard.string(forKey: "mobile.sensitivity") ?? "standard" }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "mobile.sensitivity") }
    }

    public func prepareLibrary() async {
        guard !clearing else { return }
        do {
            try await ensureLibrary()
            guard !applePreparing, !clearing else { return }
            appleStatusRevision += 1
            let revision = appleStatusRevision
            let requestedLanguage = language
            let installed = await AppleSpeechAnalyzer.isModelInstalled(locale: Locale(identifier: requestedLanguage == "en" ? "en-US" : "zh-CN"))
            guard !clearing, appleStatusRevision == revision, language == requestedLanguage else { return }
            appleReady = installed; libraryError = nil
        }
        catch { libraryError = "ios.error.library" }
    }

    func ensureLibrary() async throws {
        guard !clearing else { throw CancellationError() }
        if let libraryTask { try await libraryTask.value; return }
        guard runtime == nil else { return }
        let task = Task { try await install() }
        libraryTask = task
        defer { libraryTask = nil }
        try await task.value
    }

    func updateModels(_ snapshot: ModelCatalogSnapshot) {
        // Keep desktop-size Whisper models out of the mobile picker.
        let small = snapshot.whisper.reversed().filter { entry in
            ["tiny", "base", "small"].contains { WhisperModelSelection.matches(entry.id, variant: $0) }
        }
        models = (small + snapshot.speech).map { entry in
            let error: String?
            switch entry.status { case .error(let value), .unavailable(let value): error = value; default: error = nil }
            return MobileModel(id: entry.id, name: snapshot.whisper.contains(where: { $0.id == entry.id }) ? "Whisper " + entry.displayName : entry.displayName, detail: entry.downloadDetail,
                               bytes: entry.cacheSize, progress: entry.downloadProgress,
                               downloading: entry.status.isBusy,
                               downloaded: entry.status == .downloaded || entry.status == .ready,
                               error: error, experimental: snapshot.speech.contains { $0.id == entry.id })
        }
    }

    func requireDownloadedModel() throws {
        guard models.contains(where: { $0.id == selectedModel && $0.downloaded && !$0.downloading }) else {
            throw MobileError.localUnavailable
        }
    }

    public func selectModel(_ id: String) async {
        guard canChangeConfiguration, id == "apple" || models.contains(where: { $0.id == id && $0.downloaded }) else { return }
        modelMutation = id
        defer { modelMutation = nil }
        await disable()
        selectedModel = id
        UserDefaults.standard.set(id, forKey: "mobile.model")
    }

    public func downloadModel(_ id: String) async {
        guard !clearing, modelMutation != id, let model = models.first(where: { $0.id == id }), !model.downloading,
              let catalog = try? runtime?.service(ModelServices.catalog) else { return }
        if model.experimental { await catalog.downloadASR(id, onProgress: nil) }
        else { await catalog.downloadWhisper(id) }
    }

    public func cancelDownload(_ id: String) {
        guard let model = models.first(where: { $0.id == id }) else { return }
        (try? runtime?.service(ModelServices.catalog))?.cancelDownload(id, kind: model.experimental ? .asr : .whisper)
    }

    public func deleteModel(_ id: String) async {
        guard canChangeConfiguration, let model = models.first(where: { $0.id == id }),
              let catalog = try? runtime?.service(ModelServices.catalog) else { return }
        modelMutation = id
        defer { modelMutation = nil }
        if selectedModel == id {
            await disable()
            selectedModel = "apple"
            UserDefaults.standard.set("apple", forKey: "mobile.model")
        }
        if model.experimental { await catalog.deleteASR(id) }
        else { await catalog.deleteWhisper(id) }
    }

    public func prepareAppleModel() async {
        guard !applePreparing, canChangeConfiguration else { return }
        let requestedLanguage = language
        appleStatusRevision += 1
        applePreparing = true
        let task = Task {
            try await AppleSpeechAnalyzer.prepare(locale: Locale(identifier: requestedLanguage == "en" ? "en-US" : "zh-CN"))
            try Task.checkCancellation()
        }
        appleTask = task
        defer { applePreparing = false; appleTask = nil }
        do {
            try await task.value
            guard !clearing, language == requestedLanguage else { return }
            appleReady = true; libraryError = nil
        } catch is CancellationError {} catch { if !clearing { libraryError = "ios.error.local_unavailable" } }
    }

    public func cancelApplePreparation() { appleTask?.cancel() }

    public func changeLanguage(_ value: String) async {
        guard canChangeConfiguration, ["zh", "en"].contains(value) else { return }
        modelMutation = selectedModel
        defer { modelMutation = nil }
        await disable()
        language = value; appleReady = false
        await prepareLibrary()
    }
}
#endif
