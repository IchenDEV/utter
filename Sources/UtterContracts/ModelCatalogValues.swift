import Foundation

/// LLM model family categories
package enum CatalogModelFamily: String, CaseIterable, Sendable {
    case qwen = "Qwen"
    case gemma = "Gemma"
    case llama = "Llama"

    package var icon: String {
        switch self {
        case .qwen: return "q.circle.fill"
        case .gemma: return "g.circle.fill"
        case .llama: return "l.circle.fill"
        }
    }

    package var description: String {
        switch self {
        case .qwen: return L("model.family.qwen")
        case .gemma: return L("model.family.gemma")
        case .llama: return L("model.family.llama")
        }
    }
}

/// Curated tier used to surface the best models and fold outdated ones.
package enum CatalogModelTier: Int, CaseIterable, Sendable {
    case recommended = 0
    case standard = 1
    case legacy = 2
}

package struct CatalogModelEntry: Identifiable, Equatable, Sendable {
    package let id: String
    package let displayName: String
    package let hint: String
    package let family: CatalogModelFamily?
    package var tier: CatalogModelTier = .standard
    package var status: CatalogModelStatus = .notDownloaded
    package var cacheSize: Int64 = 0
    package var downloadProgress: Double = 0
    package var downloadDetail: String = ""
    package var benchmarkTPS: Double?
    package var isBenchmarking: Bool = false
    package var compatibility: ModelCompatibility = .compatible

    package init(id: String, displayName: String, hint: String, family: CatalogModelFamily?, tier: CatalogModelTier = .standard) {
        self.id = id
        self.displayName = displayName
        self.hint = hint
        self.family = family
        self.tier = tier
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status &&
        lhs.cacheSize == rhs.cacheSize && lhs.downloadProgress == rhs.downloadProgress &&
        lhs.downloadDetail == rhs.downloadDetail &&
        lhs.benchmarkTPS == rhs.benchmarkTPS && lhs.isBenchmarking == rhs.isBenchmarking
    }
}

package enum CatalogModelStatus: Equatable, Sendable {
    case notDownloaded, downloading, compiling, loading, downloaded, ready
    case unavailable(String)
    case error(String)

    package var isDownloading: Bool { if case .downloading = self { return true }; return false }
    package var isError: Bool { if case .error = self { return true }; return false }
    package var isBusy: Bool {
        switch self { case .downloading, .compiling, .loading: return true; default: return false }
    }
    package var canDelete: Bool {
        switch self {
        case .downloaded, .ready, .unavailable, .error: return true
        default: return false
        }
    }
}

