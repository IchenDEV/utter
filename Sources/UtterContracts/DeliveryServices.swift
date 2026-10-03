import Foundation
import UtterRuntime

package enum DeliveryDisposition: Equatable { case notCommitted, accepted, uncertain }
package enum DeliveryEffect: Equatable { case none, clipboard, paste, keyPress }

@MainActor
package protocol OutputTargetLease: AnyObject {
    var id: UUID { get }
    var processIdentifier: Int32 { get }
    var context: InputContext { get }
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
    package init(id: UUID, command: DeliveryCommand, target: (any OutputTargetLease)? = nil) {
        self.id = id
        self.command = command
        self.target = target
    }
}

package struct DeliveryReceipt {
    package let operationID: UUID
    package let disposition: DeliveryDisposition
    package let effect: DeliveryEffect
    package let reason: String?
    package let anchor: (any OutputAnchor)?

    package init(operationID: UUID, disposition: DeliveryDisposition, effect: DeliveryEffect,
                 reason: String? = nil, anchor: (any OutputAnchor)? = nil) {
        self.operationID = operationID
        self.disposition = disposition
        self.effect = effect
        self.reason = reason
        self.anchor = anchor
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
