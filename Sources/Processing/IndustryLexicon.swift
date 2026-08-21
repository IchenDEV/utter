import Foundation

struct IndustryLexiconTerm: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let term: String
    let aliases: [String]
    let category: String
    let riskLevel: String?
}

struct IndustryLexiconDocument: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let editionID: String
    let source: String
    let sourceVersion: String
    let licenseOrRights: String
    let updatedAt: String
    let terms: [IndustryLexiconTerm]
}

struct IndustryLexicon: Equatable, Sendable {
    static let shared = loadBundled()

    let editionID: String
    let source: String
    let sourceVersion: String
    let licenseOrRights: String
    let updatedAt: String
    let terms: [IndustryLexiconTerm]

    var recognitionPhrases: [String] {
        var seen = Set<String>()
        return terms.flatMap { [$0.term] + $0.aliases }.compactMap { phrase in
            let normalized = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  seen.insert(normalized.lowercased()).inserted else { return nil }
            return normalized
        }
    }

    var promptDescription: String {
        terms.map { item in
            guard !item.aliases.isEmpty else { return item.term }
            return "\(item.term)（\(item.aliases.joined(separator: "、"))）"
        }.joined(separator: "\n")
    }

    static func decode(_ data: Data, expectedEditionID: String = ProductEdition.current.id) throws -> IndustryLexicon {
        let document = try JSONDecoder().decode(IndustryLexiconDocument.self, from: data)
        guard document.schemaVersion == 1, document.editionID == expectedEditionID else {
            throw IndustryLexiconError.profileMismatch
        }
        let validTerms = document.terms.filter {
            !$0.id.isEmpty && !$0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard validTerms.count == document.terms.count else {
            throw IndustryLexiconError.invalidTerm
        }
        return IndustryLexicon(
            editionID: document.editionID,
            source: document.source,
            sourceVersion: document.sourceVersion,
            licenseOrRights: document.licenseOrRights,
            updatedAt: document.updatedAt,
            terms: validTerms
        )
    }

    private static func loadBundled() -> IndustryLexicon {
        guard let url = AppResources.bundle.url(forResource: "MedicalLexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let lexicon = try? decode(data) else {
            return IndustryLexicon(
                editionID: ProductEdition.current.id,
                source: "",
                sourceVersion: "",
                licenseOrRights: "",
                updatedAt: "",
                terms: []
            )
        }
        return lexicon
    }
}

enum IndustryLexiconError: Error {
    case profileMismatch
    case invalidTerm
}
