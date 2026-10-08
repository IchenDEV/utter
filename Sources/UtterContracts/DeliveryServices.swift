import Foundation
import UtterRuntime

package enum DeliveryDisposition: Equatable { case notCommitted, accepted, uncertain }
package enum DeliveryEffect: Hashable { case none, clipboard, paste, keyPress, accessibility }
package enum DeliveryConfirmation: String, Codable, Sendable { case none, clipboardValue, targetValue }
package enum DeliveryStatus: String, Codable, Sendable { case inserted, copied, uncertain, notDelivered }

@MainActor
package protocol OutputTargetLease: AnyObject {
    var id: UUID { get }
    var processIdentifier: Int32 { get }
    var context: InputContext { get }
    var selectedText: String? { get }
    var isValid: Bool { get }
    var isCurrent: Bool { get }
}

@MainActor
package protocol OutputAnchor: AnyObject {
    var target: any OutputTargetLease { get }
    var range: NSRange { get }
    var text: String { get }
    var expiresAt: Date { get }
    var isCurrent: Bool { get }
    func correctionSeed(context: InputContext) -> CorrectionCaptureSeed?
}

package enum DeliveryCommand {
    case insert(String)
    case replaceSelection(String)
    case deleteSelection
    case replaceAnchor(String, any OutputAnchor)
    case undoAnchor(any OutputAnchor)
    case clipboard(String)
}

package struct DeliveryRequest {
    package let id: UUID
    package let command: DeliveryCommand
    package let target: (any OutputTargetLease)?
    package let allowsClipboardPaste: Bool
    package init(id: UUID, command: DeliveryCommand, target: (any OutputTargetLease)? = nil, allowsClipboardPaste: Bool = true) {
        self.id = id
        self.command = command
        self.target = target
        self.allowsClipboardPaste = allowsClipboardPaste
    }
}

package struct DeliveryReceipt {
    package let operationID: UUID
    package let disposition: DeliveryDisposition
    package let effects: Set<DeliveryEffect>
    package let confirmation: DeliveryConfirmation
    package var effect: DeliveryEffect {
        [.accessibility, .paste, .keyPress, .clipboard].first { effects.contains($0) } ?? .none
    }
    package var isConfirmedInsertion: Bool {
        disposition == .accepted && confirmation == .targetValue
            && !effects.isDisjoint(with: [.accessibility, .paste, .keyPress])
    }
    package var status: DeliveryStatus {
        if isConfirmedInsertion { return .inserted }
        if disposition == .accepted, confirmation == .clipboardValue { return .copied }
        return disposition == .notCommitted ? .notDelivered : .uncertain
    }
    package let reason: String?
    package let anchor: (any OutputAnchor)?

    package init(operationID: UUID, disposition: DeliveryDisposition, effect: DeliveryEffect,
                 reason: String? = nil, anchor: (any OutputAnchor)? = nil,
                 effects: Set<DeliveryEffect>? = nil, confirmation: DeliveryConfirmation = .none) {
        self.operationID = operationID
        let committed = (effects ?? (effect == .none ? [] : [effect])).subtracting([.none])
        let insertionConfirmed = confirmation == .targetValue && !committed.isDisjoint(with: [.accessibility, .paste, .keyPress])
        let copyConfirmed = confirmation == .clipboardValue && committed == [.clipboard]
        self.disposition = committed.isEmpty ? .notCommitted
            : disposition == .accepted && (insertionConfirmed || copyConfirmed) ? .accepted : .uncertain
        self.effects = committed
        self.confirmation = self.disposition == .accepted ? confirmation : .none
        self.reason = reason
        self.anchor = self.disposition == .accepted && insertionConfirmed ? anchor : nil
    }
}

@MainActor
package protocol PreparedDelivery: AnyObject {
    var receipt: DeliveryReceipt? { get }
    func commit() async -> DeliveryReceipt
    func close() async
}

@MainActor
package protocol OutputService: AnyObject {
    func prepare(_ request: DeliveryRequest, isSessionCurrent: @escaping () -> Bool) throws -> any PreparedDelivery
}

package enum DeliveryError: Error, Equatable { case busy, closed, invalidTarget }

package enum MacServices {
    package static let output = ServiceKey<any OutputService>("mac.output")
}

@MainActor
extension OutputTargetLease {
    package var selectedText: String? { context.selectedText }
}
