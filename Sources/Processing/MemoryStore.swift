import Foundation
import UtterContracts
import UtterData
import UtterPresentationContracts

@MainActor
extension MemoryStore {
    static func recentContext(
        limit: Int = 5,
        windowMinutes: Int = 30,
        currentContext: InputContext? = nil
    ) -> String {
        recentContext(
            records: InputHistory.shared.records,
            currentContext: currentContext,
            limit: limit,
            windowMinutes: windowMinutes
        )
    }

}
