import Foundation

package struct ModelMemoryRequirements: Equatable, Sendable {
    package let minimumGB: Double
    package let recommendedGB: Double
    package init(minimumGB: Double, recommendedGB: Double) {
        self.minimumGB = minimumGB
        self.recommendedGB = recommendedGB
    }
    package var isValid: Bool {
        minimumGB.isFinite && recommendedGB.isFinite && minimumGB > 0 && recommendedGB >= minimumGB
    }
}

package struct ModelArtifact: Equatable, Sendable {
    package let id: String
    package let kind: ModelDownloadKind
    package let displayName: String
    package let hint: String
    package let family: CatalogModelFamily?
    package let tier: CatalogModelTier
    package let requiredFiles: [String]
    package let rank: Int
    package let repositories: [String]
    package let memoryRequirements: ModelMemoryRequirements?

    package init(id: String, kind: ModelDownloadKind, displayName: String, hint: String = "",
                 family: CatalogModelFamily? = nil, tier: CatalogModelTier = .standard,
                 requiredFiles: [String] = [], repositories: [String]? = nil, rank: Int = 0,
                 memoryRequirements: ModelMemoryRequirements? = nil) {
        self.rank = rank
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.hint = hint
        self.family = family
        self.tier = tier
        self.requiredFiles = requiredFiles
        self.repositories = repositories ?? [id]
        self.memoryRequirements = memoryRequirements
    }
}
