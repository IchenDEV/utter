import ApplicationServices
import Foundation
import UtterContracts

@MainActor
final class NativeOutputAnchor: OutputAnchor {
    let target: any OutputTargetLease
    let range: NSRange
    let text: String
    let expiresAt: Date
    private let state: AXTargetState
    private let isOwnerCurrent: () -> Bool

    init(target: any OutputTargetLease, anchor: RecentInsertionAnchor, state: AXTargetState,
         isCurrent: @escaping () -> Bool) {
        self.target = NativeTargetLease(id: target.id, processIdentifier: state.processIdentifier,
            state: state, context: target.context, isCurrent: { isCurrent() && target.isValid })
        range = anchor.range
        text = anchor.text
        expiresAt = Date().addingTimeInterval(15)
        self.state = state
        isOwnerCurrent = isCurrent
    }

    var isCurrent: Bool {
        guard isOwnerCurrent(), Date() < expiresAt, let current = AXTargetState.capture(), state.matches(current),
              let document = AXTargetState.value(of: current.element) else { return false }
        return RecentInsertionGuard.isReplacementSafe(sameTarget: true, currentSelection: current.selection,
            insertedRange: range, currentText: document, inserted: text)
    }

    func correctionSeed(context: InputContext) -> CorrectionCaptureSeed? {
        guard isCurrent, let document = AXTargetState.value(of: state.element),
              let locator = CorrectionCaptureRegionLocator(documentText: document, insertedRange: range) else { return nil }
        return CorrectionCaptureSeed(observation: AXCorrectionObservation(
            processIdentifier: state.processIdentifier, element: state.element, locator: locator, context: context
        ), insertedText: text, context: context)
    }
}
