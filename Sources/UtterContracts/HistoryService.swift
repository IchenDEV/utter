import Foundation

@MainActor
package protocol HistoryService: AnyObject {
    var records: [InputRecord] { get }
    var stats: InputStats { get }
    var storageAvailable: Bool { get }
    @discardableResult func addRecord(_ record: InputRecord) -> UUID
    @discardableResult func replaceRecord(recordID: UUID, processedText: String, context: InputContext?, formatKind: TextFormatKind?) -> UUID?
    func updateUserFinalText(recordID: UUID, text: String)
    func deleteRecord(_ id: UUID)
    func clearAll()
    func observe(_ callback: @escaping @MainActor () -> Void) -> UUID
    func removeObserver(_ id: UUID)
}

@MainActor
package protocol MemoryService: AnyObject {
    func recentContext(limit: Int, windowMinutes: Int, currentContext: InputContext?) -> String
}
