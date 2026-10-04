import Foundation

package struct ModelArtifact: Equatable, Sendable {
    package let id: String
    package let kind: ModelDownloadKind
    package let displayName: String
    package let hint: String
    package let family: CatalogModelFamily?
    package let tier: CatalogModelTier
    package let requiredFiles: [String]
    package let repositories: [String]

    package init(id: String, kind: ModelDownloadKind, displayName: String, hint: String = "",
                 family: CatalogModelFamily? = nil, tier: CatalogModelTier = .standard,
                 requiredFiles: [String] = [], repositories: [String]? = nil) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.hint = hint
        self.family = family
        self.tier = tier
        self.requiredFiles = requiredFiles
        self.repositories = repositories ?? [id]
    }
}
