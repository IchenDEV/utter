import Foundation

struct DictionaryEntry: Codable, Identifiable, Sendable {
    var id = UUID()
    var original: String
    var replacement: String
    var enabled: Bool = true
}

struct EditRule: Codable, Identifiable, Sendable {
    var id = UUID()
    var description: String
    var enabled: Bool = true
}

struct PersonalDictionarySnapshot: Sendable {
    let entries: [DictionaryEntry]
    let editRules: [EditRule]

    func applyReplacements(to text: String) -> String {
        let rules = entries.enumerated().compactMap { offset, entry -> ReplacementRule? in
            let original = entry.original
            let replacement = entry.replacement
            guard entry.enabled,
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
            .filter(\.enabled)
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

    var protectedTerms: [String] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard entry.enabled else { return nil }
            let term = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty,
                  seen.insert(term.lowercased()).inserted else {
                return nil
            }
            return term
        }
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

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenType", isDirectory: true)
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
        PersonalDictionarySnapshot(entries: entries, editRules: editRules)
    }

    func addEntry(original: String, replacement: String) {
        entries.append(DictionaryEntry(original: original, replacement: replacement))
        save()
    }

    func removeEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
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
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries) {
            try? data.write(to: entriesURL)
        }
        if let data = try? encoder.encode(editRules) {
            try? data.write(to: rulesURL)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: entriesURL),
           let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            entries = decoded
        }
        if let data = try? Data(contentsOf: rulesURL),
           let decoded = try? JSONDecoder().decode([EditRule].self, from: data) {
            editRules = decoded
        }
    }

}

private struct ReplacementRule {
    let original: String
    let replacement: String
    let insertionOrder: Int
}
