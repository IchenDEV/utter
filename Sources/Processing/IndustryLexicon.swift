import Foundation

enum IndustryLexiconID: String, Codable, CaseIterable, Identifiable, Sendable {
    case general
    case medical
    case legal
    case finance
    case technology

    var id: String { rawValue }

    var label: String { L("industry.lexicon.\(rawValue)") }

    var symbolName: String {
        switch self {
        case .general: return "text.book.closed"
        case .medical: return "cross.case"
        case .legal: return "building.columns"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .technology: return "server.rack"
        }
    }
}

struct IndustryLexiconCorrection: Codable, Equatable, Sendable {
    let recognized: String
    let preferred: String
}

struct IndustryLexiconTerm: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let term: String
    let aliases: [String]
    let corrections: [String]
    let category: String
}

struct IndustryLexiconSource: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let url: String
    let usage: String
    let redistribution: String
}

struct IndustryLexiconPack: Codable, Equatable, Identifiable, Sendable {
    let id: IndustryLexiconID
    let version: String
    let locale: String
    let reviewStatus: String
    let sourceIDs: [String]
    let terms: [IndustryLexiconTerm]
}

private struct IndustryLexiconDocument: Codable, Sendable {
    let schemaVersion: Int
    let version: String
    let updatedAt: String
    let rights: String
    let sources: [IndustryLexiconSource]
    let packs: [IndustryLexiconPack]
}

struct IndustryLexiconSnapshot: Equatable, Sendable {
    static let maximumRecognitionPhrases = 100
    static let maximumPromptTerms = 80
    static let maximumPromptCharacters = 2000

    static let empty = IndustryLexiconSnapshot(pack: nil)

    let pack: IndustryLexiconPack?

    var recognitionPhrases: [String] {
        guard let pack else { return [] }
        return Array(unique(pack.terms.prefix(Self.maximumRecognitionPhrases).flatMap { [$0.term] + $0.aliases })
            .prefix(Self.maximumRecognitionPhrases))
    }

    var protectedTerms: [String] {
        guard let pack else { return [] }
        // Imported common words are hints, not mandatory literal-output constraints.
        return unique(pack.terms.filter { $0.category != "thuocl-common" }.map(\.term))
    }

    var corrections: [IndustryLexiconCorrection] {
        guard let pack else { return [] }
        return pack.terms.flatMap { item in
            item.corrections.map {
                IndustryLexiconCorrection(recognized: $0, preferred: item.term)
            }
        }
    }

    var promptDescription: String { promptDescription(matching: "") }

    func promptDescription(matching transcript: String) -> String {
        guard let pack else { return "" }
        let text = transcript.lowercased()
        let matching = text.isEmpty ? [] : pack.terms.filter { item in
            ([item.term] + item.aliases + item.corrections).contains {
                text.contains($0.lowercased())
            }
        }.sorted { $0.term.count > $1.term.count }
        let candidates = matching + pack.terms.prefix(Self.maximumPromptTerms)
        var seen = Set<String>()
        var lines: [String] = []
        var characters = 0
        for item in candidates {
            guard seen.insert(item.id).inserted else { continue }
            let line = item.aliases.isEmpty ? item.term
                : "\(item.term)（\(item.aliases.joined(separator: "、"))）"
            let cost = line.count + (lines.isEmpty ? 0 : 1)
            guard characters + cost <= Self.maximumPromptCharacters else { continue }
            lines.append(line)
            characters += cost
            if lines.count == Self.maximumPromptTerms { break }
        }
        return lines.joined(separator: "\n")
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  seen.insert(normalized.lowercased()).inserted else { return nil }
            return normalized
        }
    }
}

struct IndustryLexiconCatalog: Sendable {
    static let shared = loadBundled()

    let version: String
    let updatedAt: String
    let rights: String
    let sources: [IndustryLexiconSource]
    let packs: [IndustryLexiconPack]

    func pack(for id: IndustryLexiconID) -> IndustryLexiconPack? {
        guard id != .general else { return nil }
        return packs.first { $0.id == id }
    }

    func snapshot(for id: IndustryLexiconID) -> IndustryLexiconSnapshot {
        IndustryLexiconSnapshot(pack: pack(for: id))
    }

    static func decode(_ data: Data) throws -> IndustryLexiconCatalog {
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
        guard let url = AppResources.bundle.url(
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
}

enum IndustryLexiconError: Error {
    case unsupportedSchema
    case invalidDocument
    case invalidSource
    case duplicatePack
    case invalidPack
    case invalidTerm
}
