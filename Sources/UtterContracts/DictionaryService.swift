import Foundation

package protocol DictionaryService: AnyObject {
    var entries: [DictionaryEntry] { get set }
    var editRules: [EditRule] { get set }
    func snapshot(industryLexicon: IndustryLexiconSnapshot, bundleIdentifier: String?, languageCode: String?) -> PersonalDictionarySnapshot
    @discardableResult func addEntry(original: String, replacement: String) -> UUID?
    func removeEntry(at offsets: IndexSet)
    func removeEntry(id: UUID)
    func updateEntry(id: UUID, original: String, replacement: String)
    func setEntryEnabled(id: UUID, enabled: Bool)
    func approveEntry(id: UUID)
    func addRule(description: String)
    func removeRule(at offsets: IndexSet)
    func clearLearnedEntries()
    @discardableResult func recordLearnedCandidate(_ candidate: LearnedCorrectionCandidate) -> UUID?
    func exportData() throws -> Data
    @discardableResult func importEntries(from data: Data) throws -> Int
    func save()
    func observe(_ callback: @escaping () -> Void) -> UUID
    func removeObserver(_ id: UUID)
}
