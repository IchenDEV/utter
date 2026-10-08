import UtterPresentationContracts
import UtterContracts
import UtterRuntime
import Combine
import Foundation
import WhisperKit

@MainActor
package final class ModelCatalog: ObservableObject, ModelCatalogService {

    @Published package var whisperModels: [ModelEntry] = [] { didSet { notifyObservers() } }
    @Published package var llmModels: [ModelEntry] = [] { didSet { notifyObservers() } }
    @Published package var asrModels: [ModelEntry] = [] { didSet { notifyObservers() } }

    package let settings: AppSettings
    let storage: ConfiguredModelStorage
    let log: Log
    let access: any ModelResourceAccess
    let textDownloads: TextModelDownloadOperations
    var artifactsByID: [String: ModelArtifact] = [:]
    let speechDescriptors: () -> [ProviderDescriptor]
    package let downloadTasks = ModelDownloadTasks()
    private var startupCleanupTask: Task<Int, Never>?
    private let startupStorageRoot: URL
    private let startupCleanup: StartupCleanupFactory
    private(set) var closed = false
    let progressTasks = CallbackTasks()
    var observers: [UUID: (ModelCatalogSnapshot) -> Void] = [:]
    var watchdogs: [DownloadStallWatchdog] = []

    package typealias ModelFamily = CatalogModelFamily
    package typealias ModelTier = CatalogModelTier
    package typealias ModelEntry = CatalogModelEntry
    package typealias ModelStatus = CatalogModelStatus

    private static let curatedWhisperVariants = [
        "large-v3-turbo", "large-v3", "large-v2", "medium", "small", "base", "tiny",
    ]

    /// Internal construction seam used to exercise the real startup wiring
    /// against a path-scoped cleanup task. Production callers use the
    /// detached ModelStorage default below.
    package typealias StartupCleanupFactory = (URL) -> Task<Int, Never>

    package init(
        settings: AppSettings, log: Log, access: any ModelResourceAccess, textDownloads: TextModelDownloadOperations,
        artifacts: [ModelArtifact] = [], speechDescriptors: @escaping () -> [ProviderDescriptor] = { [] },
        startupStorageRoot: URL? = nil,
        startupCleanup: @escaping StartupCleanupFactory = { storageRoot in
            ModelStorage.cleanupOrphanedGenerationStagingInBackground(storageRoot: storageRoot)
        }
    ) {
        // A previous process may have exited before a cancelled writer could
        // run its cleanup. Reclaim those roots away from the MainActor and
        // gate fresh download entry points on this task below.
        self.settings = settings
        storage = ConfiguredModelStorage(settings: { settings.snapshot })
        self.log = log
        self.access = access
        self.textDownloads = textDownloads
        self.speechDescriptors = speechDescriptors
        self.startupStorageRoot = startupStorageRoot ?? storage.root
        self.startupCleanup = startupCleanup
        let rec = WhisperKit.recommendedModels()
        let defaultID = rec.default
        let supported = Set(rec.supported)

        whisperModels = Self.curatedWhisperVariants.compactMap { variant in
            let fullName = WhisperModelSelection.matches(defaultID, variant: variant)
                ? defaultID
                : rec.supported.first {
                    WhisperModelSelection.matches($0, variant: variant)
                }
            guard let fullName, supported.contains(fullName) else { return nil }
            return ModelEntry(
                id: fullName,
                displayName: Self.shortenWhisperName(fullName),
                hint: fullName == defaultID ? L("common.recommended") : "",
                family: nil
            )
        }

        appendLocalWhisperModels()
        loadArtifacts(artifacts)
    }

    /// Startup cleanup may remove model-sized trees. Download entry points
    /// await its detached task before admitting a new writer, while the
    /// MainActor remains available for UI and Cancel/Delete arbitration.
    package func start() {
        guard !closed, startupCleanupTask == nil else { return }
        startupCleanupTask = startupCleanup(startupStorageRoot)
    }

    package func revoke() {
        guard !closed else { return }
        closed = true
        observers.removeAll()
        startupCleanupTask?.cancel()
        progressTasks.revoke()
        downloadTasks.revoke()
        for watchdog in watchdogs { watchdog.stop() }
    }

    package func close() async {
        revoke()
        await downloadTasks.close()
        await progressTasks.close()
        for watchdog in watchdogs { await watchdog.close() }
        watchdogs.removeAll()
        _ = await startupCleanupTask?.value
    }

    package func awaitStartupCleanup() async {
        guard !closed else { return }
        start()
        _ = await startupCleanupTask?.value
    }

    package static func shortenWhisperName(_ name: String) -> String {
        var s = name
        s = s.replacingOccurrences(of: "openai_whisper-", with: "")
        s = s.replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")

        var sizeSuffix = ""
        if let range = s.range(of: "_\\d+MB$", options: .regularExpression) {
            sizeSuffix = " (" + s[range].dropFirst() + ")"
            s = String(s[s.startIndex..<range.lowerBound])
        }
        s = s.replacingOccurrences(of: "_", with: " ")
        return s + sizeSuffix
    }

    // MARK: - Status

    package func refreshStatus(recheckingErrors: Bool = false) {
        guard !closed else { return }
        for i in whisperModels.indices where !whisperModels[i].status.isBusy {
            let id = whisperModels[i].id
            let size = whisperVariantSize(id)
            whisperModels[i].cacheSize = size
            if recheckingErrors || (whisperModels[i].status != .ready && !whisperModels[i].status.isError) {
                let isComplete = isWhisperDownloaded(id)
                if storage.localWhisperURL(id) != nil, !isComplete {
                    whisperModels[i].status = .error(L("model.local_missing"))
                } else {
                    whisperModels[i].status = isComplete
                        ? .downloaded
                        : (size > 0 ? .error(L("model.download_incomplete")) : .notDownloaded)
                }
            }
        }
        for i in llmModels.indices where !llmModels[i].status.isBusy {
            let id = llmModels[i].id
            let size = llmRepoSize(id)
            llmModels[i].cacheSize = size
            if recheckingErrors || (llmModels[i].status != .ready && !llmModels[i].status.isError) {
                let isComplete = llmRepoIsComplete(id)
                if storage.localLLMURL(id) != nil, !isComplete {
                    llmModels[i].status = .error(L("model.local_missing"))
                } else {
                    llmModels[i].status = isComplete
                        ? .downloaded
                        : (size > 0 ? .error(L("model.download_incomplete")) : .notDownloaded)
                }
            }
            llmModels[i].compatibility = DeviceCapability.check(
                modelID: id,
                downloadSizeBytes: Self.defaultDownloadEstimateBytes(for: id),
                memoryRequirements: artifactsByID[id]?.memoryRequirements
            )
        }
        refreshASRStatus(recheckingErrors: recheckingErrors)
    }

    package func addCustomLLM(_ modelID: String) {
        guard !closed else { return }
        guard !modelID.isEmpty, !llmModels.contains(where: { $0.id == modelID }) else { return }
        let name = modelID.components(separatedBy: "/").last ?? modelID
        llmModels.append(ModelEntry(id: modelID, displayName: name, hint: L("common.custom"), family: nil))
        refreshStatus()
    }

    package func addLocalWhisper(_ url: URL) {
        guard !closed else { return }
        let existing = Set(whisperModels.map(\.id))
        let id = ModelStorage.makeLocalID(prefix: "whisper", folderName: url.lastPathComponent, existing: existing)
        var paths = settings.localWhisperModelPaths
        paths[id] = url.path
        settings.localWhisperModelPaths = paths
        whisperModels.append(ModelEntry(id: id, displayName: url.lastPathComponent, hint: L("model.local"), family: nil))
        settings.whisperModel = id
        refreshStatus()
    }

    package func addLocalLLM(_ url: URL) {
        guard !closed else { return }
        let existing = Set(llmModels.map(\.id))
        let id = ModelStorage.makeLocalID(prefix: "llm", folderName: url.lastPathComponent, existing: existing)
        var paths = settings.localLLMModelPaths
        paths[id] = url.path
        settings.localLLMModelPaths = paths
        llmModels.append(ModelEntry(id: id, displayName: url.lastPathComponent, hint: L("model.local"), family: nil))
        settings.llmModel = id
        refreshStatus()
    }

    // MARK: - Download status

    package func updateWhisperStatus(_ id: String, status: ModelStatus, detail: String = "") {
        guard !closed else { return }
        guard let i = whisperModels.firstIndex(where: { $0.id == id }) else { return }
        whisperModels[i].status = status
        whisperModels[i].downloadDetail = detail
        if status == .ready || status == .downloaded {
            whisperModels[i].cacheSize = whisperVariantSize(id)
        }
    }

    package func updateLLMStatus(_ id: String, status: ModelStatus, detail: String = "") {
        guard !closed else { return }
        guard let i = llmModels.firstIndex(where: { $0.id == id }) else { return }
        llmModels[i].status = status
        llmModels[i].downloadDetail = detail
        if llmModels[i].status == .ready || llmModels[i].status == .downloaded {
            llmModels[i].cacheSize = llmRepoSize(id)
        }
    }

    // MARK: - Cache Utilities

    package static func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", Double(bytes) / 1e9) }
        if bytes >= 1_000_000 { return String(format: "%.1f MB", Double(bytes) / 1e6) }
        if bytes >= 1_000 { return String(format: "%.0f KB", Double(bytes) / 1e3) }
        return "\(bytes) B"
    }

    private func appendLocalWhisperModels() {
        for (id, path) in settings.localWhisperModelPaths.sorted(by: { $0.key < $1.key }) {
            guard !whisperModels.contains(where: { $0.id == id }) else { continue }
            let name = URL(fileURLWithPath: path).lastPathComponent
            whisperModels.append(ModelEntry(id: id, displayName: name, hint: L("model.local"), family: nil))
        }
    }

    func appendLocalLLMModels() {
        for (id, path) in settings.localLLMModelPaths.sorted(by: { $0.key < $1.key }) {
            guard !llmModels.contains(where: { $0.id == id }) else { continue }
            let name = URL(fileURLWithPath: path).lastPathComponent
            llmModels.append(ModelEntry(id: id, displayName: name, hint: L("model.local"), family: nil))
        }
    }
}
