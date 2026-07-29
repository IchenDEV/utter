import Foundation
import WhisperKit

@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()

    @Published var whisperModels: [ModelEntry] = []
    @Published var llmModels: [ModelEntry] = []
    @Published var asrModels: [ModelEntry] = []

    let settings = AppSettings.shared
    let downloadTasks = ModelDownloadTasks()

    /// LLM model family categories
    enum ModelFamily: String, CaseIterable {
        case qwen = "Qwen"
        case gemma = "Gemma"
        case llama = "Llama"

        var icon: String {
            switch self {
            case .qwen: return "q.circle.fill"
            case .gemma: return "g.circle.fill"
            case .llama: return "l.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .qwen: return L("model.family.qwen")
            case .gemma: return L("model.family.gemma")
            case .llama: return L("model.family.llama")
            }
        }
    }

    /// Curated tier used to surface the best models and fold outdated ones.
    enum ModelTier: Int, CaseIterable {
        case recommended = 0
        case standard = 1
        case legacy = 2
    }

    struct ModelEntry: Identifiable, Equatable {
        let id: String
        let displayName: String
        let hint: String
        let family: ModelFamily?
        var tier: ModelTier = .standard
        var status: ModelStatus = .notDownloaded
        var cacheSize: Int64 = 0
        var downloadProgress: Double = 0
        var downloadDetail: String = ""
        var benchmarkTPS: Double?
        var isBenchmarking: Bool = false

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.status == rhs.status &&
            lhs.cacheSize == rhs.cacheSize && lhs.downloadProgress == rhs.downloadProgress &&
            lhs.downloadDetail == rhs.downloadDetail &&
            lhs.benchmarkTPS == rhs.benchmarkTPS && lhs.isBenchmarking == rhs.isBenchmarking
        }
    }

    enum ModelStatus: Equatable {
        case notDownloaded, downloading, compiling, loading, downloaded, ready
        case unavailable(String)
        case error(String)

        var isDownloading: Bool { if case .downloading = self { return true }; return false }
        var isError: Bool { if case .error = self { return true }; return false }
        var isBusy: Bool {
            switch self { case .downloading, .compiling, .loading: return true; default: return false }
        }
        var canDelete: Bool {
            switch self {
            case .downloaded, .ready, .unavailable, .error: return true
            default: return false
            }
        }
    }

    private static let curatedWhisperVariants = [
        "large-v3-turbo", "large-v3", "large-v2", "medium", "small", "base", "tiny",
    ]

    private init() {
        let rec = WhisperKit.recommendedModels()
        let defaultID = rec.default
        let supported = Set(rec.supported)

        whisperModels = Self.curatedWhisperVariants.compactMap { variant in
            let fullName = rec.supported.first { name in
                guard let range = name.range(of: variant) else { return false }
                let after = name[range.upperBound...]
                return after.isEmpty || after.first == "_"
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
        if !whisperModels.contains(where: { $0.id == settings.whisperModel }) {
            settings.whisperModel = defaultID
        }

        llmModels = Self.defaultLLMModels.map {
            ModelEntry(id: $0.0, displayName: $0.1, hint: $0.2, family: $0.3, tier: $0.4)
        }
        appendLocalLLMModels()
        if !llmModels.contains(where: { $0.id == settings.llmModel }) {
            settings.llmModel = llmModels.first?.id ?? ""
        }

        asrModels = Self.defaultASRModels.map {
            ModelEntry(id: $0.id, displayName: $0.displayName, hint: $0.hint, family: nil)
        }
        if !asrModels.contains(where: { $0.id == settings.qwenASRModel }) {
            settings.qwenASRModel = LocalASRConfiguration.qwen3DefaultModel
        }
        if !asrModels.contains(where: { $0.id == settings.mimoASRModel }) {
            settings.mimoASRModel = LocalASRConfiguration.mimoDefaultModel
        }
        refreshStatus()
    }

    static var defaultLLMModels: [(String, String, String, ModelFamily?, ModelTier)] {
        [
            // Qwen Family
            ("mlx-community/Qwen3.5-0.8B-MLX-4bit", "Qwen3.5 0.8B", L("model.qwen35_tiny"), .qwen, .recommended),
            ("mlx-community/Qwen3.5-2B-4bit", "Qwen3.5 2B", L("model.qwen35_fast"), .qwen, .recommended),
            ("mlx-community/Qwen3.5-9B-5bit", "Qwen3.5 9B", L("model.qwen35_quality"), .qwen, .recommended),
            ("mlx-community/Qwen3-30B-A3B-4bit", "Qwen3 30B-A3B", L("model.qwen3_moe"), .qwen, .recommended),
            ("mlx-community/Qwen3.5-35B-A3B-4bit", "Qwen3.5 35B-A3B", L("model.qwen35_moe"), .qwen, .standard),
            ("mlx-community/Qwen2.5-0.5B-Instruct-4bit", "Qwen2.5 0.5B", L("model.smallest"), .qwen, .legacy),
            ("mlx-community/Qwen2.5-1.5B-Instruct-4bit", "Qwen2.5 1.5B", L("model.balanced"), .qwen, .legacy),
            ("mlx-community/Qwen2.5-3B-Instruct-4bit", "Qwen2.5 3B", L("model.best_quality"), .qwen, .legacy),
            ("mlx-community/Qwen3-0.6B-4bit", "Qwen3 0.6B", L("model.qwen3_fast"), .qwen, .legacy),
            ("mlx-community/Qwen3-1.7B-4bit", "Qwen3 1.7B", L("model.qwen3_balanced"), .qwen, .legacy),
            ("mlx-community/Qwen3-4B-4bit", "Qwen3 4B", L("model.qwen3_quality"), .qwen, .legacy),

            // Gemma Family (Google)
            ("mlx-community/gemma-4-e2b-it-4bit", "Gemma 4 E2B", L("model.gemma4_edge"), .gemma, .recommended),
            ("mlx-community/gemma-4-e4b-it-4bit", "Gemma 4 E4B", L("model.gemma4_edge_quality"), .gemma, .standard),
            ("mlx-community/gemma-3-1b-it-4bit", "Gemma 3 1B", L("model.gemma_fast"), .gemma, .legacy),
            ("mlx-community/gemma-3-4b-it-4bit", "Gemma 3 4B", L("model.gemma_balanced"), .gemma, .legacy),
            ("mlx-community/gemma-3-12b-it-4bit", "Gemma 3 12B", L("model.gemma_quality"), .gemma, .legacy),

            // Llama Family (Meta)
            ("mlx-community/Llama-4-Scout-17B-16E-Instruct-4bit", "Llama 4 Scout", L("model.llama_balanced"), .llama, .recommended),
            ("mlx-community/Llama-4-Maverick-17B-128E-Instruct-4bit", "Llama 4 Maverick", L("model.llama_quality"), .llama, .standard),
        ]
    }

    // MARK: - Display Name

    static func shortenWhisperName(_ name: String) -> String {
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

    func refreshStatus(recheckingErrors: Bool = false) {
        for i in whisperModels.indices where !whisperModels[i].status.isBusy {
            let id = whisperModels[i].id
            let size = whisperVariantSize(id)
            whisperModels[i].cacheSize = size
            if recheckingErrors || (whisperModels[i].status != .ready && !whisperModels[i].status.isError) {
                let isComplete = isWhisperDownloaded(id)
                if ModelStorage.localWhisperURL(id) != nil, !isComplete {
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
                if ModelStorage.localLLMURL(id) != nil, !isComplete {
                    llmModels[i].status = .error(L("model.local_missing"))
                } else {
                    llmModels[i].status = isComplete
                        ? .downloaded
                        : (size > 0 ? .error(L("model.download_incomplete")) : .notDownloaded)
                }
            }
        }
        refreshASRStatus(recheckingErrors: recheckingErrors)
    }

    func addCustomLLM(_ modelID: String) {
        guard !modelID.isEmpty, !llmModels.contains(where: { $0.id == modelID }) else { return }
        let name = modelID.components(separatedBy: "/").last ?? modelID
        llmModels.append(ModelEntry(id: modelID, displayName: name, hint: L("common.custom"), family: nil))
        refreshStatus()
    }

    func addLocalWhisper(_ url: URL) {
        let existing = Set(whisperModels.map(\.id))
        let id = ModelStorage.makeLocalID(prefix: "whisper", folderName: url.lastPathComponent, existing: existing)
        var paths = settings.localWhisperModelPaths
        paths[id] = url.path
        settings.localWhisperModelPaths = paths
        whisperModels.append(ModelEntry(id: id, displayName: url.lastPathComponent, hint: L("model.local"), family: nil))
        settings.whisperModel = id
        refreshStatus()
    }

    func addLocalLLM(_ url: URL) {
        let existing = Set(llmModels.map(\.id))
        let id = ModelStorage.makeLocalID(prefix: "llm", folderName: url.lastPathComponent, existing: existing)
        var paths = settings.localLLMModelPaths
        paths[id] = url.path
        settings.localLLMModelPaths = paths
        llmModels.append(ModelEntry(id: id, displayName: url.lastPathComponent, hint: L("model.local"), family: nil))
        settings.llmModel = id
        refreshStatus()
    }

    // MARK: - External Status Updates (called by VoicePipeline)

    func updateWhisperStatus(_ id: String, status: ModelStatus, detail: String = "") {
        guard let i = whisperModels.firstIndex(where: { $0.id == id }) else { return }
        whisperModels[i].status = status
        whisperModels[i].downloadDetail = detail
        if status == .ready || status == .downloaded {
            whisperModels[i].cacheSize = whisperVariantSize(id)
        }
    }

    func updateLLMStatus(_ id: String, status: ModelStatus, detail: String = "") {
        guard let i = llmModels.firstIndex(where: { $0.id == id }) else { return }
        llmModels[i].status = status
        llmModels[i].downloadDetail = detail
        if llmModels[i].status == .ready || llmModels[i].status == .downloaded {
            llmModels[i].cacheSize = llmRepoSize(id)
        }
    }

    // MARK: - Cache Utilities

    static func formatBytes(_ bytes: Int64) -> String {
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

    private func appendLocalLLMModels() {
        for (id, path) in settings.localLLMModelPaths.sorted(by: { $0.key < $1.key }) {
            guard !llmModels.contains(where: { $0.id == id }) else { continue }
            let name = URL(fileURLWithPath: path).lastPathComponent
            llmModels.append(ModelEntry(id: id, displayName: name, hint: L("model.local"), family: nil))
        }
    }
}
