import Foundation
import UtterContracts

@MainActor
protocol DeliveryPasteboard: AnyObject {
    var changeCount: Int { get }
    var text: String? { get }
    func snapshot() -> [[String: Data]]
    func write(_ text: String) -> Bool
    func restore(_ items: [[String: Data]])
}

@MainActor
enum ClipboardPasteTransaction {
    static func copy(_ text: String, pasteboard: any DeliveryPasteboard,
                     canCommit: () -> Bool, mark: (DeliveryEffect) -> Bool) -> DeliveryCompletion {
        guard canCommit(), mark(.clipboard) else { return DeliveryCompletion(disposition: .notCommitted) }
        let written = pasteboard.write(text)
        return DeliveryCompletion(disposition: written && pasteboard.text == text ? .accepted : .uncertain,
            confirmation: written && pasteboard.text == text ? .clipboardValue : .none)
    }

    static func paste(_ text: String, pasteboard: any DeliveryPasteboard,
                      canCommit: () -> Bool, mark: (DeliveryEffect) -> Bool,
                      postPaste: () -> Bool, confirm: @escaping () async -> Bool,
                      beforePaste: () async -> Void = { await Task.yield() }) async -> DeliveryCompletion {
        guard canCommit() else { return DeliveryCompletion(disposition: .notCommitted) }
        let previous = pasteboard.snapshot()
        guard canCommit(), mark(.clipboard) else { return DeliveryCompletion(disposition: .notCommitted) }
        guard pasteboard.write(text) else { return DeliveryCompletion(disposition: .uncertain) }
        let ownedChange = pasteboard.changeCount
        func stillOwnsClipboard() -> Bool { pasteboard.changeCount == ownedChange && pasteboard.text == text }
        await beforePaste()
        guard canCommit(), stillOwnsClipboard(), mark(.paste) else {
            if stillOwnsClipboard() { pasteboard.restore(previous) }
            return DeliveryCompletion(disposition: .uncertain)
        }
        // Once posting is attempted, neither a retry nor clipboard restoration
        // is safe until the original target proves it consumed this payload.
        guard postPaste() else { return DeliveryCompletion(disposition: .uncertain) }
        let observation = Task { @MainActor in await confirm() }
        let confirmed = await observation.value
        if confirmed && stillOwnsClipboard() { pasteboard.restore(previous) }
        return DeliveryCompletion(disposition: confirmed ? .accepted : .uncertain,
            confirmation: confirmed ? .targetValue : .none)
    }
}
