import Foundation
import UtterContracts

private struct IndustryLexiconDocument: Codable, Sendable {
    let schemaVersion: Int
    let version: String
    let updatedAt: String
    let rights: String
    let sources: [IndustryLexiconSource]
    let packs: [IndustryLexiconPack]
}

package struct IndustryLexiconCatalog: LexiconService {
    package static let shared = loadBundled()

    package let version: String
    package let updatedAt: String
    package let rights: String
    package let sources: [IndustryLexiconSource]
    package let packs: [IndustryLexiconPack]

    package func pack(for id: IndustryLexiconID) -> IndustryLexiconPack? {
        guard id != .general else { return nil }
        return packs.first { $0.id == id }
    }

    package func snapshot(for id: IndustryLexiconID) -> IndustryLexiconSnapshot {
        IndustryLexiconSnapshot(pack: pack(for: id))
    }

    package static func decode(_ data: Data) throws -> IndustryLexiconCatalog {
        let document = try JSONDecoder().decode(IndustryLexiconDocument.self, from: data)
        guard document.schemaVersion == 1 else { throw IndustryLexiconError.unsupportedSchema }
        guard !document.version.isEmpty,
              !document.updatedAt.isEmpty,
              !document.rights.isEmpty else {
            throw IndustryLexiconError.invalidDocument
        }
        guard Set(document.sources.map(\.id)).count == document.sources.count,
              document.sources.allSatisfy({ source in
                  !source.id.isEmpty
                      && !source.title.isEmpty
                      && URL(string: source.url)?.scheme?.hasPrefix("http") == true
                      && ((source.usage == "reference-only" && source.redistribution == "not-redistributed")
                          || (source.usage == "redistributed-terms" && source.redistribution == "MIT"))
              }) else {
            throw IndustryLexiconError.invalidSource
        }
        guard Set(document.packs.map(\.id)).count == document.packs.count,
              !document.packs.contains(where: { $0.id == .general }) else {
            throw IndustryLexiconError.duplicatePack
        }
        let sourceIDs = Set(document.sources.map(\.id))
        for pack in document.packs {
            guard !pack.version.isEmpty,
                  pack.locale == "zh-CN",
                  ["project-seed-needs-domain-review", "curated-and-imported-needs-domain-review"]
                    .contains(pack.reviewStatus),
                  !pack.terms.isEmpty,
                  Set(pack.terms.map(\.id)).count == pack.terms.count,
                  !pack.sourceIDs.isEmpty,
                  Set(pack.sourceIDs).isSubset(of: sourceIDs) else {
                throw IndustryLexiconError.invalidPack
            }
            var canonicalTerms = Set<String>()
            var recognizedCorrections = Set<String>()
            for item in pack.terms {
                let term = item.term.trimmingCharacters(in: .whitespacesAndNewlines)
                let canonicalKey = term.lowercased()
                let aliasKeys = item.aliases.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                guard !item.id.isEmpty,
                      !term.isEmpty,
                      !item.category.isEmpty,
                      canonicalTerms.insert(canonicalKey).inserted,
                      !aliasKeys.contains(""),
                      !aliasKeys.contains(canonicalKey),
                      Set(aliasKeys).count == aliasKeys.count else {
                    throw IndustryLexiconError.invalidTerm
                }
                for correction in item.corrections {
                    let normalized = correction.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalized.isEmpty,
                          normalized.caseInsensitiveCompare(term) != .orderedSame,
                          recognizedCorrections.insert(normalized.lowercased()).inserted else {
                        throw IndustryLexiconError.invalidTerm
                    }
                }
            }
        }
        return IndustryLexiconCatalog(
            version: document.version,
            updatedAt: document.updatedAt,
            rights: document.rights,
            sources: document.sources,
            packs: document.packs
        )
    }

    private static func loadBundled() -> IndustryLexiconCatalog {
        guard let url = DataResources.bundle.url(
            forResource: "IndustryLexicons",
            withExtension: "json"
        ), let data = try? Data(contentsOf: url), let catalog = try? decode(data) else {
            return IndustryLexiconCatalog(
                version: "",
                updatedAt: "",
                rights: "",
                sources: [],
                packs: []
            )
        }
        return catalog
    }

    package init(version: String, updatedAt: String, rights: String, sources: [IndustryLexiconSource], packs: [IndustryLexiconPack]) {
        self.version = version
        self.updatedAt = updatedAt
        self.rights = rights
        self.sources = sources
        self.packs = packs
    }
}

package enum IndustryLexiconError: Error {
    case unsupportedSchema
    case invalidDocument
    case invalidSource
    case duplicatePack
    case invalidPack
    case invalidTerm
}
