import Foundation
import UtterContracts

@MainActor
protocol DeliveryTextTarget: AnyObject {
    var isCurrent: Bool { get }
    var supportsSelectionWrite: Bool { get }
    /// A Chromium web content editor: an Accessibility write there reports success without effect.
    var isWebContentEditor: Bool { get }
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
        let kind: DeliveryTargetKind = target.isWebContentEditor ? .web : .native
        var path: DeliveryPath?
        var result = await run(text, target: target, pasteboard: pasteboard, allowsClipboardPaste: allowsClipboardPaste,
                               isSecureInput: isSecureInput, prepareKeys: prepareKeys, canCommit: canCommit, mark: mark, path: &path)
        result.path = path
        result.target = kind
        return result
    }

    private static func run(_ text: String, target: any DeliveryTextTarget, pasteboard: any DeliveryPasteboard,
                            allowsClipboardPaste: Bool, isSecureInput: () -> Bool,
                            prepareKeys: (_ deleting: Bool) -> (() -> Bool)?,
                            canCommit: () -> Bool, mark: (DeliveryEffect) -> Bool,
                            path: inout DeliveryPath?) async -> DeliveryCompletion {
        func mayWrite() -> Bool {
            !isSecureInput() && canCommit() && !isSecureInput() && target.isCurrent && !isSecureInput()
        }
        guard mayWrite(), target.prepareSelection() else {
            return DeliveryCompletion(disposition: .notCommitted, reason: L("delivery.target_changed"))
        }
        var documentEffect = false
        defer { if !documentEffect && !isSecureInput() { target.restoreSelection() } }
        func markDocument(_ effect: DeliveryEffect) -> Bool {
            guard mark(effect), mayWrite() else { return false }
            if effect != .clipboard { documentEffect = true }
            return true
        }
        guard mayWrite() else { return DeliveryCompletion(disposition: .notCommitted) }
        // Checked here as well as in the target so no target can reach the ineffective write by mistake.
        if target.supportsSelectionWrite, !target.isWebContentEditor {
            path = .accessibility
            guard mayWrite(), markDocument(.accessibility) else { return DeliveryCompletion(disposition: .notCommitted) }
            guard target.writeSelection(text) else {
                return DeliveryCompletion(disposition: .uncertain, reason: L("delivery.unconfirmed"))
            }
            let observation = Task { @MainActor in await target.confirm(text) }
            let confirmed = await observation.value
            return DeliveryCompletion(disposition: confirmed ? .accepted : .uncertain,
                reason: confirmed ? nil : L("delivery.unconfirmed"), confirmation: confirmed ? .targetValue : .none)
        }
        guard allowsClipboardPaste else {
            return DeliveryCompletion(disposition: .notCommitted, reason: L("delivery.unavailable"))
        }
        guard let post = prepareKeys(text.isEmpty) else {
            guard !text.isEmpty else { return DeliveryCompletion(disposition: .notCommitted, reason: L("delivery.unavailable")) }
            path = .clipboardOnly
            return ClipboardPasteTransaction.copy(text, pasteboard: pasteboard, canCommit: mayWrite, mark: markDocument)
        }
        if text.isEmpty {
            path = .keyPress
            guard mayWrite(), !isSecureInput(), markDocument(.keyPress), post() else {
                return DeliveryCompletion(disposition: documentEffect ? .uncertain : .notCommitted)
            }
            let observation = Task { @MainActor in await target.confirm(text) }
            let confirmed = await observation.value
            return DeliveryCompletion(disposition: confirmed ? .accepted : .uncertain,
                reason: confirmed ? nil : L("delivery.unconfirmed"), confirmation: confirmed ? .targetValue : .none)
        }
        path = .paste
        var result = await ClipboardPasteTransaction.paste(text, pasteboard: pasteboard,
            canCommit: { mayWrite() && !isSecureInput() }, mark: markDocument,
            postPaste: post, confirm: { await target.confirm(text) })
        if result.disposition == .uncertain { result.reason = L("delivery.unconfirmed") }
        return result
    }
}
