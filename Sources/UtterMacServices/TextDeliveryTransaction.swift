import Foundation
import UtterContracts

@MainActor
protocol DeliveryTextTarget: AnyObject {
    var isCurrent: Bool { get }
    var supportsSelectionWrite: Bool { get }
    func prepareSelection() -> Bool
    func writeSelection(_ text: String) -> Bool
    func confirm(_ text: String) async -> Bool
    func restoreSelection()
}

@MainActor
enum TextDeliveryTransaction {
    static func deliver(_ text: String, target: any DeliveryTextTarget, pasteboard: any DeliveryPasteboard,
                        allowsClipboardPaste: Bool, isSecureInput: () -> Bool,
                        prepareKeys: (_ deleting: Bool) -> (() -> Bool)?,
                        canCommit: () -> Bool, mark: (DeliveryEffect) -> Bool) async -> DeliveryCompletion {
        guard canCommit(), target.isCurrent, target.prepareSelection() else {
            return DeliveryCompletion(disposition: .notCommitted, reason: L("delivery.target_changed"))
        }
        var documentEffect = false
        defer { if !documentEffect { target.restoreSelection() } }
        func mayWrite() -> Bool { canCommit() && target.isCurrent }
        func markDocument(_ effect: DeliveryEffect) -> Bool {
            guard mark(effect) else { return false }
            if effect != .clipboard { documentEffect = true }
            return true
        }
        if target.supportsSelectionWrite {
            guard mayWrite(), markDocument(.accessibility) else { return DeliveryCompletion(disposition: .notCommitted) }
            guard target.writeSelection(text) else {
                return DeliveryCompletion(disposition: .uncertain, reason: L("delivery.unconfirmed"))
            }
            let observation = Task { @MainActor in await target.confirm(text) }
            let confirmed = await observation.value
            return DeliveryCompletion(disposition: confirmed ? .accepted : .uncertain,
                reason: confirmed ? nil : L("delivery.unconfirmed"), confirmation: confirmed ? .targetValue : .none)
        }
        guard allowsClipboardPaste, !isSecureInput(), let post = prepareKeys(text.isEmpty) else {
            guard !text.isEmpty else { return DeliveryCompletion(disposition: .notCommitted, reason: L("delivery.unavailable")) }
            return ClipboardPasteTransaction.copy(text, pasteboard: pasteboard, canCommit: mayWrite, mark: mark)
        }
        if text.isEmpty {
            guard mayWrite(), !isSecureInput(), markDocument(.keyPress), post() else {
                return DeliveryCompletion(disposition: documentEffect ? .uncertain : .notCommitted)
            }
            let observation = Task { @MainActor in await target.confirm(text) }
            let confirmed = await observation.value
            return DeliveryCompletion(disposition: confirmed ? .accepted : .uncertain,
                reason: confirmed ? nil : L("delivery.unconfirmed"), confirmation: confirmed ? .targetValue : .none)
        }
        var result = await ClipboardPasteTransaction.paste(text, pasteboard: pasteboard,
            canCommit: { mayWrite() && !isSecureInput() }, mark: markDocument,
            postPaste: post, confirm: { await target.confirm(text) })
        if result.disposition == .uncertain { result.reason = L("delivery.unconfirmed") }
        return result
    }
}
