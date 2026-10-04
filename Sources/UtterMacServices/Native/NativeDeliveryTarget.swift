import AppKit
import ApplicationServices
import Foundation
import UtterContracts

@MainActor
final class NativeDeliveryTarget: DeliveryTextTarget {
    private let lease: any OutputTargetLease
    private let identity: AXUIElement
    private let original: AXTargetState?
    private let document: String?
    private let replacementRange: NSRange?
    private var prepared = false
    private let clock: any DeliveryObservationClock

    init?(lease: any OutputTargetLease, anchor: (any OutputAnchor)?, requiresSelection: Bool,
          clock: (any DeliveryObservationClock)? = nil) {
        guard lease.isCurrent, let (pid, element) = AXTargetState.focusedIdentity(), pid == lease.processIdentifier else { return nil }
        let state = AXTargetState.capture()
        let value = AXTargetState.value(of: element)
        if requiresSelection, (state?.selection.length ?? 0) == 0 { return nil }
        if let anchor {
            guard anchor.isCurrent, state != nil, let value,
                  DeliveryTextChange(document: value, range: anchor.range, replacement: anchor.text) != nil,
                  (value as NSString).substring(with: anchor.range) == anchor.text else { return nil }
            replacementRange = anchor.range
        } else { replacementRange = state?.selection }
        self.lease = lease
        identity = element
        original = state
        document = value
        self.clock = clock ?? ContinuousDeliveryClock()
    }

    var isCurrent: Bool {
        guard lease.isValid, let (pid, element) = AXTargetState.focusedIdentity(),
              pid == lease.processIdentifier, CFEqual(identity, element) else { return false }
        if let document, AXTargetState.value(of: identity) != document { return false }
        if let original {
            return AXTargetState.range(of: identity) == (prepared ? replacementRange : original.selection)
        }
        return lease.isCurrent
    }

    var supportsSelectionWrite: Bool {
        guard document != nil, replacementRange != nil else { return false }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(identity, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
    }

    func prepareSelection() -> Bool {
        guard isCurrent else { return false }
        if let replacementRange, original?.selection != replacementRange {
            guard AXTargetState.setRange(replacementRange, of: identity) else { return false }
        }
        prepared = true
        return isCurrent
    }

    func writeSelection(_ text: String) -> Bool {
        AXUIElementSetAttributeValue(identity, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    func confirm(_ text: String) async -> Bool {
        // An unchanged value cannot prove that a pending paste consumed the clipboard.
        guard let expected = expectedDocument(text), expected != document else { return false }
        return await DeliveryTextObservation.confirm(expected, read: { AXTargetState.value(of: self.identity) }, clock: clock)
    }

    func restoreSelection() {
        guard prepared, isCurrent, let original else { return }
        original.restoreSelection()
    }

    func insertionAnchor(_ text: String, isCurrent: @escaping () -> Bool) -> (any OutputAnchor)? {
        guard !text.isEmpty, let range = replacementRange, let expected = expectedDocument(text),
              AXTargetState.value(of: identity) == expected, let state = AXTargetState.capture(),
              state.processIdentifier == lease.processIdentifier, CFEqual(identity, state.element) else { return nil }
        let insertedRange = NSRange(location: range.location, length: (text as NSString).length)
        let insertion = RecentInsertionAnchor(processIdentifier: lease.processIdentifier, element: identity, range: insertedRange, text: text)
        return NativeOutputAnchor(target: lease, anchor: insertion, state: state, isCurrent: isCurrent)
    }

    private func expectedDocument(_ text: String) -> String? {
        guard let document, let range = replacementRange else { return nil }
        return DeliveryTextChange(document: document, range: range, replacement: text)?.expectedDocument
    }
}
