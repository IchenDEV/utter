import Combine
import Foundation
import SwiftUI
import UtterContracts

package final class PersonalDictionary: ObservableObject {
    private let service: any DictionaryService
    private let lexicons: any LexiconService
    private var observation: UUID?

    package init(service: any DictionaryService, lexicons: any LexiconService) {
        self.service = service
        self.lexicons = lexicons
        observation = service.observe { [weak self] in self?.objectWillChange.send() }
    }

    deinit {
        if let observation { service.removeObserver(observation) }
    }

    package var entries: [DictionaryEntry] {
        get { service.entries }
        set { service.entries = newValue; service.save() }
    }

    package var storageAvailable: Bool { service.storageAvailable }

    package var editRules: [EditRule] {
        get { service.editRules }
        set { service.editRules = newValue; service.save() }
    }

    package func snapshot(industryLexicon: IndustryLexiconSnapshot = .empty, bundleIdentifier: String? = nil, languageCode: String? = nil) -> PersonalDictionarySnapshot {
        service.snapshot(industryLexicon: industryLexicon, bundleIdentifier: bundleIdentifier, languageCode: languageCode)
    }

    package func snapshot(settings: AppSettings, bundleIdentifier: String? = nil, languageCode: String? = nil) -> PersonalDictionarySnapshot {
        snapshot(industryLexicon: lexicons.snapshot(for: settings.industryLexicon), bundleIdentifier: bundleIdentifier, languageCode: languageCode)
    }

    package func applyReplacements(to text: String) -> String { snapshot().applyReplacements(to: text) }
    package func activeEntriesDescription() -> String { snapshot().activeEntriesDescription }
    package func activeRulesDescription() -> String { snapshot().activeRulesDescription }
    @discardableResult package func addEntry(original: String, replacement: String) -> UUID? { service.addEntry(original: original, replacement: replacement) }
    package func removeEntry(at offsets: IndexSet) { service.removeEntry(at: offsets) }
    package func removeEntry(id: UUID) { service.removeEntry(id: id) }
    package func updateEntry(id: UUID, original: String, replacement: String) { service.updateEntry(id: id, original: original, replacement: replacement) }
    package func setEntryEnabled(id: UUID, enabled: Bool) { service.setEntryEnabled(id: id, enabled: enabled) }
    package func approveEntry(id: UUID) { service.approveEntry(id: id) }
    package func addRule(description: String) { service.addRule(description: description) }
    package func removeRule(at offsets: IndexSet) { service.removeRule(at: offsets) }
    package func clearLearnedEntries() { service.clearLearnedEntries() }
    @discardableResult package func recordLearnedCandidate(_ candidate: LearnedCorrectionCandidate) -> UUID? { service.recordLearnedCandidate(candidate) }
    package func exportData() throws -> Data { try service.exportData() }
    @discardableResult package func importEntries(from data: Data) throws -> Int { try service.importEntries(from: data) }
    package func save() { service.save() }
}
