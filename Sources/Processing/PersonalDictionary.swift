import Foundation

struct EditRule: Codable, Identifiable, Sendable {
    var id = UUID()
    var description: String
    var enabled: Bool = true
}

struct PersonalDictionarySnapshot: Sendable {
    let entries: [DictionaryEntry]
    let editRules: [EditRule]
    let industryTerms: [String]

    init(
        entries: [DictionaryEntry],
        editRules: [EditRule],
        industryTerms: [String] = []
    ) {
        self.entries = entries
        self.editRules = editRules
        self.industryTerms = industryTerms
    }

    func applyReplacements(to text: String) -> String {
        let rules = entries.enumerated().compactMap { offset, entry -> ReplacementRule? in
            let original = entry.original
            let replacement = entry.replacement
            guard entry.isEffective,
                  !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return ReplacementRule(
                original: original,
                replacement: replacement,
                insertionOrder: offset
            )
        }
        .sorted {
            if $0.original.count != $1.original.count {
                return $0.original.count > $1.original.count
            }
            return $0.insertionOrder < $1.insertionOrder
        }

        guard !rules.isEmpty, !text.isEmpty else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if let match = rules.first(where: {
                Self.matches($0.original, in: text, at: cursor)
            }) {
                result += match.replacement
                cursor = text.index(cursor, offsetBy: match.original.count)
            } else {
                result.append(text[cursor])
                cursor = text.index(after: cursor)
            }
        }
        return result
    }

    var activeEntriesDescription: String {
        entries
            .filter(\.isEffective)
            .compactMap { entry -> String? in
                let original = entry.original.trimmingCharacters(in: .whitespacesAndNewlines)
                let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !original.isEmpty, !replacement.isEmpty else { return nil }
                return "\(original) -> \(replacement)"
            }
            .joined(separator: "\n")
    }

    var activeRulesDescription: String {
        editRules
            .filter(\.enabled)
            .map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var activeIndustryTermsDescription: String {
        industryTerms.joined(separator: "\n")
    }

    var recognitionPhrases: [String] {
        let personal = SpeechRecognitionContext(dictionaryEntries: entries).phrases
        return SpeechRecognitionContext(phrases: industryTerms + personal).phrases
    }

    var protectedTerms: [String] {
        var seen = Set<String>()
        let personalTerms = entries.compactMap { entry -> String? in
            guard entry.isEffective else { return nil }
            let term = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty,
                  seen.insert(term.lowercased()).inserted else {
                return nil
            }
            return term
        }
        let industry = industryTerms.compactMap { term -> String? in
            let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  seen.insert(normalized.lowercased()).inserted else { return nil }
            return normalized
        }
        return industry + personalTerms
    }

    private static func matches(
        _ original: String,
        in text: String,
        at start: String.Index
    ) -> Bool {
        guard let end = text.index(start, offsetBy: original.count, limitedBy: text.endIndex),
              String(text[start..<end]).compare(
                  original,
                  options: .caseInsensitive
              ) == .orderedSame else {
            return false
        }

        if let first = original.first, isASCIIWordCharacter(first),
           start > text.startIndex,
           isASCIIWordCharacter(text[text.index(before: start)]) {
            return false
        }
        if let last = original.last, isASCIIWordCharacter(last),
           end < text.endIndex,
           isASCIIWordCharacter(text[end]) {
            return false
        }
        return true
    }

    private static func isASCIIWordCharacter(_ character: Character) -> Bool {
        character.isASCIIWord
    }
}

final class PersonalDictionary: ObservableObject {
    static let shared = PersonalDictionary()

    @Published var entries: [DictionaryEntry] = []
    @Published var editRules: [EditRule] = []

    private let entriesURL: URL
    private let rulesURL: URL

    init(directoryURL: URL? = nil) {
        let dir = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent(ProductBrand.applicationSupportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        entriesURL = dir.appendingPathComponent("dictionary.json")
        rulesURL = dir.appendingPathComponent("edit_rules.json")
        load()
    }

    func applyReplacements(to text: String) -> String {
        snapshot().applyReplacements(to: text)
    }

    func activeEntriesDescription() -> String {
        snapshot().activeEntriesDescription
    }

    func activeRulesDescription() -> String {
        snapshot().activeRulesDescription
    }

    func snapshot() -> PersonalDictionarySnapshot {
        PersonalDictionarySnapshot(
            entries: entries,
            editRules: editRules,
            industryTerms: IndustryLexicon.shared.recognitionPhrases
        )
    }

    @discardableResult
    func addEntry(original: String, replacement: String) -> UUID? {
        let original = normalized(original)
        let replacement = normalized(replacement)
        guard !original.isEmpty, !replacement.isEmpty, original != replacement else { return nil }

        if let index = entries.firstIndex(where: {
            $0.original.caseInsensitiveCompare(original) == .orderedSame
        }) {
            entries[index].original = original
            entries[index].replacement = replacement
            entries[index].enabled = true
            entries[index].origin = .manual
            entries[index].status = .active
            entries[index].confidence = 1
            entries[index].evidenceCount = max(1, entries[index].evidenceCount)
            save()
            return entries[index].id
        }

        let entry = DictionaryEntry(original: original, replacement: replacement)
        entries.append(entry)
        save()
        return entry.id
    }

    func removeEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func updateEntry(id: UUID, original: String, replacement: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let original = normalized(original)
        let replacement = normalized(replacement)
        guard !original.isEmpty, !replacement.isEmpty, original != replacement else { return }
        entries[index].original = original
        entries[index].replacement = replacement
        save()
    }

    func setEntryEnabled(id: UUID, enabled: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].enabled = enabled
        save()
    }

    func approveEntry(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let original = entries[index].original
        for otherIndex in entries.indices where otherIndex != index
            && entries[otherIndex].origin == .learned
            && entries[otherIndex].original.caseInsensitiveCompare(original) == .orderedSame {
            entries[otherIndex].status = .pending
        }
        entries[index].status = .active
        entries[index].enabled = true
        save()
    }

    func addRule(description: String) {
        editRules.append(EditRule(description: description))
        save()
    }

    func removeRule(at offsets: IndexSet) {
        editRules.remove(atOffsets: offsets)
        save()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: entriesURL, options: .atomic)
        }
        if let data = try? encoder.encode(editRules) {
            try? data.write(to: rulesURL, options: .atomic)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: entriesURL),
           let decoded = try? decoder.decode([DictionaryEntry].self, from: data) {
            entries = decoded
        }
        if let data = try? Data(contentsOf: rulesURL),
           let decoded = try? decoder.decode([EditRule].self, from: data) {
            editRules = decoded
        }
    }

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

private struct ReplacementRule {
    let original: String
    let replacement: String
    let insertionOrder: Int
}
