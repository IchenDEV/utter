import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterMediaContracts
import UtterContracts
import AppKit
import XCTest
@testable import UtterPresentation

@MainActor
final class OverlayLayoutTests: XCTestCase {
    func testRecordingOverlayUsesCompactCapsuleShape() {
        let appState = AppState()
        appState.project(SessionExecutionSnapshot(phase: .recording, isBusy: true))

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
        appState.project(SessionExecutionSnapshot(phase: .recording, transcript: "A live transcription preview", isBusy: true))

        let layout = OverlayLayout(appState: appState)

        XCTAssertEqual(layout.width, 304)
        XCTAssertEqual(layout.height, 80)
        XCTAssertEqual(layout.outerCornerRadius, 22)
    }

    func testWorkingOverlaysKeepTheRecordingCapsuleHeight() {
        let appState = AppState()

        for phase in [SessionExecutionPhase.transcribing, .processing, .delivering] {
            appState.project(SessionExecutionSnapshot(phase: phase, isBusy: true))
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

    func testOverlayTargetsDisplayContainingFocusedWindow() {
        let displays = [
            CGRect(x: 0, y: 0, width: 1_512, height: 982),
            CGRect(x: -2_560, y: -323, width: 2_560, height: 1_440),
        ]
        let focusedWindow = CGRect(x: -2_200, y: -200, width: 1_000, height: 800)

        let index = OverlayPanelPlacement.targetDisplayIndex(
            for: focusedWindow,
            in: displays
        )

        XCTAssertEqual(index, 1)
    }

    func testOverlayTargetsDisplayWithMostOfFocusedWindow() {
        let displays = [
            CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            CGRect(x: 0, y: 0, width: 1_512, height: 982),
        ]
        let focusedWindow = CGRect(x: -300, y: 100, width: 1_000, height: 700)

        let index = OverlayPanelPlacement.targetDisplayIndex(
            for: focusedWindow,
            in: displays
        )

        XCTAssertEqual(index, 1)
    }

    func testOverlayHasNoTargetForWindowOutsideConnectedDisplays() {
        let displays = [CGRect(x: 0, y: 0, width: 1_512, height: 982)]
        let focusedWindow = CGRect(x: 4_000, y: 100, width: 800, height: 600)

        let index = OverlayPanelPlacement.targetDisplayIndex(
            for: focusedWindow,
            in: displays
        )

        XCTAssertNil(index)
    }


    func transcribe(audioURL: URL?, language: String?) async throws -> String { "" }
}
