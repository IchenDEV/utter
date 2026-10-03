import Foundation
import UtterContracts

@MainActor
final class HistoryMemoryService: MemoryService {
    private let history: any HistoryService

    init(history: any HistoryService) { self.history = history }

    func recentContext(limit: Int, windowMinutes: Int, currentContext: InputContext?) -> String {
        MemoryStore.recentContext(records: history.records, currentContext: currentContext, limit: limit, windowMinutes: windowMinutes)
    }
}
