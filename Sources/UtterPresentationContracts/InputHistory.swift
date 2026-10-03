import Foundation
import Combine
import SwiftUI
import UtterContracts

@MainActor
package final class InputHistory: ObservableObject {
    private let service: any HistoryService
    private var observation: UUID?

    package init(service: any HistoryService) {
        self.service = service
        observation = service.observe { [weak self] in self?.objectWillChange.send() }
    }

    package var records: [InputRecord] { service.records }
    package var stats: InputStats { service.stats }
    package var storageAvailable: Bool { service.storageAvailable }

    package func dispose() {
        if let observation { service.removeObserver(observation) }
        observation = nil
    }

    @discardableResult
    package func addRecord(rawText: String, processedText: String, wasProcessed: Bool, context: InputContext? = nil, formatKind: TextFormatKind? = nil) -> UUID {
        service.addRecord(InputRecord(rawText: rawText, processedText: processedText, wasProcessed: wasProcessed, context: context, formatKind: formatKind))
    }

    @discardableResult
    package func replaceRecord(recordID: UUID, processedText: String, context: InputContext? = nil, formatKind: TextFormatKind? = nil) -> UUID? {
        service.replaceRecord(recordID: recordID, processedText: processedText, context: context, formatKind: formatKind)
    }

    package func updateUserFinalText(recordID: UUID, text: String) { service.updateUserFinalText(recordID: recordID, text: text) }
    package func deleteRecord(_ id: UUID) { service.deleteRecord(id) }
    package func clearAll() { service.clearAll() }
}
