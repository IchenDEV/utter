import XCTest
import UtterContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
final class PresentationProjectionTests: XCTestCase {
    func testGenerationFallbackUsesTheCompletedSessionAndResetsForTheNextOne() {
        let state = AppState()
        state.project(SessionExecutionSnapshot(phase: .completed, deliveryStatus: .inserted, generationOutcome: .fallback))
        XCTAssertEqual(state.completionKind, .espressoFallback)
        XCTAssertEqual(OverlayLayout(appState: state).height, 56)
        state.project(SessionExecutionSnapshot(phase: .preparing, isBusy: true))
        XCTAssertEqual(state.completionKind, .standard)
        XCTAssertEqual(state.lastFormattingDurationSeconds, 0)
    }
    func testFailureKeepsCandidateAndRecoveryInTheVisibleOverlay() {
        let state = AppState()
        state.project(SessionExecutionSnapshot(id: UUID(), phase: .failed, text: "Candidate translation",
            error: L("translation.wrong_language"), deliveryStatus: .notDelivered, recoveryAction: .models))
        XCTAssertEqual(state.phase, .error(L("translation.wrong_language")))
        XCTAssertTrue(state.presentation.keepsVisible)
        XCTAssertTrue(state.presentation.canCopy)
        XCTAssertEqual(state.snapshot.recoveryAction, .models)
        XCTAssertTrue(OverlayLayout(appState: state).isInteractive)
    }

    func testCopyAndUncertainReceiptsCannotProjectAsInserted() {
        let state = AppState()
        state.project(SessionExecutionSnapshot(phase: .completed, text: "Result", deliveryStatus: .copied))
        XCTAssertEqual(state.phase, .copied)
        state.project(SessionExecutionSnapshot(phase: .failed, text: "Result", deliveryStatus: .uncertain))
        XCTAssertEqual(state.phase, .uncertain)
        XCTAssertTrue(state.presentation.keepsVisible)
        XCTAssertEqual(OverlayLayout(appState: state).height, 96)
        state.project(SessionExecutionSnapshot(phase: .cancelled))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertTrue(state.processedText.isEmpty)
    }
}
