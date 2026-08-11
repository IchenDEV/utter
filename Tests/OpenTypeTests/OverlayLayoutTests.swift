import AppKit
import XCTest
@testable import OpenType

@MainActor
final class OverlayLayoutTests: XCTestCase {
    func testRecordingOverlayUsesCompactCapsuleShape() {
        let appState = AppState()
        appState.phase = .recording
        appState.rawTranscription = ""

        let layout = OverlayLayout(appState: appState)

        XCTAssertEqual(layout.width, 148)
        XCTAssertEqual(layout.height, 40)
        XCTAssertEqual(layout.outerCornerRadius, layout.height / 2)
        XCTAssertEqual(layout.horizontalPadding, 7)
        XCTAssertTrue(layout.isInteractive)

        let controlsInset = (layout.width - OverlayControlMetrics.recordingControlsWidth) / 2
        let leadingButtonCenter = controlsInset + OverlayControlMetrics.actionButtonSize / 2
        XCTAssertEqual(leadingButtonCenter, layout.outerCornerRadius)
    }

    func testLivePreviewExpandsWithoutReturningToTheLargeCard() {
        let appState = AppState()
        appState.phase = .recording
        appState.rawTranscription = "A live transcription preview"

        let layout = OverlayLayout(appState: appState)

        XCTAssertEqual(layout.width, 304)
        XCTAssertEqual(layout.height, 80)
        XCTAssertEqual(layout.outerCornerRadius, 22)
    }

    func testWorkingOverlaysKeepTheRecordingCapsuleHeight() {
        let appState = AppState()

        for phase in [AppPhase.transcribing, .processing, .inserting] {
            appState.phase = phase
            let layout = OverlayLayout(appState: appState)

            XCTAssertEqual(layout.width, 216)
            XCTAssertEqual(layout.height, 40)
            XCTAssertEqual(layout.outerCornerRadius, layout.height / 2)
            XCTAssertFalse(layout.isInteractive)
        }
    }

    func testOverlayPlacementCentersAboveVisibleScreenBottom() {
        let visibleFrame = CGRect(x: 100, y: 80, width: 1_200, height: 760)
        let frame = OverlayPanelPlacement.frame(
            for: CGSize(width: 148, height: 40),
            in: visibleFrame
        )

        XCTAssertEqual(frame.midX, visibleFrame.midX)
        XCTAssertEqual(frame.minY, visibleFrame.minY + 24)
    }

    func testCancellingRecordingResetsStateWithoutProcessing() {
        let appState = AppState()
        appState.phase = .recording
        appState.rawTranscription = "Discard me"
        let pipeline = VoicePipeline(appState: appState)

        pipeline.cancel()

        XCTAssertEqual(appState.phase, .idle)
        XCTAssertEqual(appState.rawTranscription, "")
    }
}
