import Foundation

@MainActor
package protocol CorrectionObservationSource: AnyObject {
    var isEligible: Bool { get }
    var isFocused: Bool { get }
    func readEditedText() -> String?
    func observe(_ callback: @escaping () -> Void) -> UUID?
    func removeObserver(_ id: UUID)
}

package struct CorrectionCaptureSeed {
    package let observation: any CorrectionObservationSource
    package let insertedText: String
    package let context: InputContext

    package init(observation: any CorrectionObservationSource, insertedText: String, context: InputContext) {
        self.observation = observation
        self.insertedText = insertedText
        self.context = context
    }
}
