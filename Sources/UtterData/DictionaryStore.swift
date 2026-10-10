import Foundation
import UtterContracts

package final class DictionaryStore: DictionaryService {

    package var entries: [DictionaryEntry] = []
    package var editRules: [EditRule] = []

    private let entriesURL: URL
    private let rulesURL: URL
    private let reportError: (String) -> Void
    private var entriesWritable = true
    private var rulesWritable = true
    private var observers: [UUID: () -> Void] = [:]

    package var storageAvailable: Bool { entriesWritable && rulesWritable }

    package init(directoryURL: URL? = nil, reportError: @escaping (String) -> Void = { _ in }) {
        self.reportError = reportError
        let dir = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent(ProductBrand.applicationSupportDirectoryName, isDirectory: true)
        entriesURL = dir.appendingPathComponent("dictionary.json")
        rulesURL = dir.appendingPathComponent("edit_rules.json")
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch {
            entriesWritable = false
            rulesWritable = false
            reportError("Cannot create dictionary directory: \(error.localizedDescription)")
        }
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
        if entriesWritable {
            do { try encoder.encode(entries).write(to: entriesURL, options: .atomic) }
            catch {
                entriesWritable = false
                reportError("Cannot save dictionary: \(error.localizedDescription)")
            }
        }
        if rulesWritable {
            do { try encoder.encode(editRules).write(to: rulesURL, options: .atomic) }
            catch {
                rulesWritable = false
                reportError("Cannot save edit rules: \(error.localizedDescription)")
            }
        }
        for id in observers.keys.sorted(by: { $0.uuidString < $1.uuidString }) { observers[id]?() }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            entries = try read([DictionaryEntry].self, from: entriesURL, decoder: decoder).map { entry in
                var entry = entry
                if entry.origin == .learned,
                   LearnedCorrectionPolicy.isUnsafeSource(entry.original) {
                    entry.status = .pending
                }
                return entry
            }
        } catch {
            entriesWritable = false
            reportError("Cannot read dictionary; original file preserved: \(error.localizedDescription)")
        }
        do { editRules = try read([EditRule].self, from: rulesURL, decoder: decoder) }
        catch {
            rulesWritable = false
            reportError("Cannot read edit rules; original file preserved: \(error.localizedDescription)")
        }
    }

    private func read<Value: Decodable>(_ type: [Value].Type, from url: URL, decoder: JSONDecoder) throws -> [Value] {
        do { return try decoder.decode(type, from: Data(contentsOf: url)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
    }

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
