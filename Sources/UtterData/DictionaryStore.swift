import Foundation
import UtterContracts

package final class DictionaryStore: DictionaryService {

    package var entries: [DictionaryEntry] = []
    package var editRules: [EditRule] = []

    private let entriesURL: URL
    private let rulesURL: URL
    private var observers: [UUID: () -> Void] = [:]

    package init(directoryURL: URL? = nil) {
        let dir = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent(ProductBrand.applicationSupportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        entriesURL = dir.appendingPathComponent("dictionary.json")
        rulesURL = dir.appendingPathComponent("edit_rules.json")
        load()
    }

    package func applyReplacements(to text: String) -> String {
        snapshot().applyReplacements(to: text)
    }

    package func activeEntriesDescription() -> String {
        snapshot().activeEntriesDescription
    }

    package func activeRulesDescription() -> String {
        snapshot().activeRulesDescription
    }

    package func snapshot(
        industryLexicon: IndustryLexiconSnapshot = .empty,
        bundleIdentifier: String? = nil,
        languageCode: String? = nil
    ) -> PersonalDictionarySnapshot {
        PersonalDictionarySnapshot(
            entries: entries,
            editRules: editRules,
            industryLexicon: industryLexicon,
            bundleIdentifier: bundleIdentifier,
            languageCode: languageCode
        )
    }

    @discardableResult
    package func addEntry(original: String, replacement: String) -> UUID? {
        let original = normalized(original)
        let replacement = normalized(replacement)
        guard !original.isEmpty, !replacement.isEmpty, original != replacement else { return nil }

        let matches = entries.indices.filter {
            entries[$0].original.caseInsensitiveCompare(original) == .orderedSame
        }
        if let index = matches.first(where: { entries[$0].origin == .manual }) ?? matches.first {
            entries[index].original = original
            entries[index].replacement = replacement
            entries[index].enabled = true
            entries[index].origin = .manual
            entries[index].status = .active
            entries[index].confidence = 1
            entries[index].evidenceCount = max(1, entries[index].evidenceCount)
            entries[index].languageCode = nil
            entries[index].appScopes = []
            suspendLearnedMappings(for: original, excluding: entries[index].id)
            save()
            return entries[index].id
        }

        let entry = DictionaryEntry(original: original, replacement: replacement)
        entries.append(entry)
        suspendLearnedMappings(for: original, excluding: entry.id)
        save()
        return entry.id
    }

    package func removeEntry(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { entries.remove(at: index) }
        save()
    }

    package func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    package func updateEntry(id: UUID, original: String, replacement: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let original = normalized(original)
        let replacement = normalized(replacement)
        guard !original.isEmpty, !replacement.isEmpty, original != replacement else { return }
        entries[index].original = original
        entries[index].replacement = replacement
        entries[index].origin = .manual
        entries[index].status = .active
        entries[index].languageCode = nil
        entries[index].appScopes = []
        suspendLearnedMappings(for: original, excluding: entries[index].id)
        save()
    }

    package func setEntryEnabled(id: UUID, enabled: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].enabled = enabled
        save()
    }

    package func approveEntry(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if entries[index].origin == .learned,
           LearnedCorrectionPolicy.isUnsafeSource(entries[index].original) {
            entries[index].origin = .manual
            entries[index].languageCode = nil
            entries[index].appScopes = []
        }
        let original = entries[index].original
        if entries[index].origin == .manual {
            suspendLearnedMappings(for: original, excluding: entries[index].id)
        } else {
            for otherIndex in entries.indices where otherIndex != index
                && entries[otherIndex].origin == .learned
                && entries[otherIndex].original.caseInsensitiveCompare(original) == .orderedSame
                && entries[otherIndex].languageCode == entries[index].languageCode
                && entries[otherIndex].appScopes == entries[index].appScopes {
                entries[otherIndex].status = .pending
            }
        }
        entries[index].status = .active
        entries[index].enabled = true
        save()
    }

    package func addRule(description: String) {
        editRules.append(EditRule(description: description))
        save()
    }

    package func removeRule(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { editRules.remove(at: index) }
        save()
    }

    package func observe(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }

    package func removeObserver(_ id: UUID) { observers[id] = nil }

    package func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: entriesURL, options: .atomic)
        }
        if let data = try? encoder.encode(editRules) {
            try? data.write(to: rulesURL, options: .atomic)
        }
        for id in observers.keys.sorted(by: { $0.uuidString < $1.uuidString }) { observers[id]?() }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: entriesURL),
           let decoded = try? decoder.decode([DictionaryEntry].self, from: data) {
            entries = decoded.map { entry in
                var entry = entry
                if entry.origin == .learned,
                   LearnedCorrectionPolicy.isUnsafeSource(entry.original) {
                    entry.status = .pending
                }
                return entry
            }
        }
        if let data = try? Data(contentsOf: rulesURL),
           let decoded = try? decoder.decode([EditRule].self, from: data) {
            editRules = decoded
        }
    }

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
