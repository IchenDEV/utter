import AppKit
import XCTest
import UtterContracts
import UtterPresentationContracts
@testable import UtterPresentation

/// The error and unconfirmed-insertion notice used to be a fixed 360 x 96 card. Its size now follows its content.
@MainActor
final class OverlayAlertLayoutTests: XCTestCase {
    private let previousCardHeight: CGFloat = 96

    override func tearDown() {
        Loc.use(.chinese)
        super.tearDown()
    }

    private func state(_ snapshot: SessionExecutionSnapshot) -> AppState {
        let state = AppState()
        state.project(snapshot)
        return state
    }

    private func unconfirmed(error: String? = L("delivery.unconfirmed")) -> SessionExecutionSnapshot {
        SessionExecutionSnapshot(phase: .failed, text: "text", error: error, deliveryStatus: .uncertain)
    }

    func testUnconfirmedInsertionIsOneCompactRowInBothLanguages() {
        for (language, maximum) in [(UILanguage.chinese, CGFloat(46)), (.english, 58)] {
            Loc.use(language)
            for snapshot in [unconfirmed(), unconfirmed(error: nil)] {
                let appState = state(snapshot)
                let layout = OverlayLayout(appState: appState)
                let plan = OverlayAlertMetrics.plan(for: OverlayAlert(appState: appState))

                XCTAssertEqual(layout.content, .alert)
                XCTAssertEqual(layout.width, 360)
                XCTAssertLessThanOrEqual(layout.height, maximum, "\(language)")
                XCTAssertLessThan(layout.height, previousCardHeight)
                XCTAssertTrue(layout.isInteractive)
                XCTAssertEqual(plan.arrangement, .inline, "Copy and Close share the row with the message")
                XCTAssertEqual(plan.capsuleWidths.count, 1, "Copy is offered because there is text to copy")
                XCTAssertEqual(layout.panelSize, plan.size)
            }
        }
    }

    func testErrorsKeepTheirActionOnTheRowAndAreNotTallerThanThreeLines() {
        for language in [UILanguage.chinese, .english] {
            Loc.use(language)
            let cases = [
                SessionExecutionSnapshot(phase: .failed, error: L("pipeline.model_load_failed"), recoveryAction: .models),
                SessionExecutionSnapshot(phase: .failed, error: L("screen.permission_required"), recoveryAction: .screenPrivacy),
                SessionExecutionSnapshot(phase: .failed, text: "text", error: L("delivery.unavailable"), deliveryStatus: .notDelivered),
            ]
            for snapshot in cases {
                let appState = state(snapshot)
                let plan = OverlayAlertMetrics.plan(for: OverlayAlert(appState: appState))
                XCTAssertEqual(plan.arrangement, .inline, "\(language): \(appState.statusMessage)")
                XCTAssertLessThanOrEqual(plan.size.height, 58, "\(language): \(appState.statusMessage)")
                XCTAssertLessThanOrEqual(plan.titleLines + plan.detailLines, OverlayAlertMetrics.maxLines)
                XCTAssertEqual(OverlayLayout(appState: appState).content, .alert)
            }
        }
    }

    func testOnlyAMessageTooLongForTheRowStacksItsButtonsAndStillStaysBelowTheOldCard() {
        Loc.use(.english)
        let sentences = String(repeating: "A very long error sentence that keeps going. ", count: 6)
        let oneRun = String(repeating: "word ", count: 80)
        for error in [sentences, oneRun] {
            let appState = state(SessionExecutionSnapshot(phase: .failed, text: "text", error: error,
                                                          deliveryStatus: .notDelivered, recoveryAction: .models))
            let plan = OverlayAlertMetrics.plan(for: OverlayAlert(appState: appState))
            XCTAssertEqual(plan.arrangement, .stacked)
            XCTAssertLessThanOrEqual(plan.titleLines + plan.detailLines, OverlayAlertMetrics.maxLines, "Never more than three lines")
            XCTAssertLessThan(plan.size.height, previousCardHeight)
            XCTAssertEqual(plan.capsuleWidths.count, 2, "Copy and the recovery action both stay reachable")
        }
    }

    func testOtherPhasesDoNotUseTheAlertLayout() {
        for snapshot in [
            SessionExecutionSnapshot(phase: .completed, text: "text", deliveryStatus: .copied),
            SessionExecutionSnapshot(phase: .completed, text: "text", deliveryStatus: .inserted),
            SessionExecutionSnapshot(phase: .recording, isBusy: true),
            SessionExecutionSnapshot(phase: .processing, isBusy: true),
        ] {
            XCTAssertEqual(OverlayLayout(appState: state(snapshot)).content, .status)
        }
    }

    func testMessageSplitsIntoTitleAndDetailAtTheFirstSentence() {
        func parts(_ message: String) -> [String?] {
            let (title, detail) = OverlayAlert(message: message, isUncertain: true).parts
            return [title, detail]
        }
        XCTAssertEqual(parts("无法确认是否已写入。可以复制文本，Utter 不会自动再次写入。"),
                       ["无法确认是否已写入。", "可以复制文本，Utter 不会自动再次写入。"])
        XCTAssertEqual(parts("Insertion could not be confirmed. The text is available to copy."),
                       ["Insertion could not be confirmed.", "The text is available to copy."])
        XCTAssertEqual(parts("Really? Yes."), ["Really?", "Yes."])
        XCTAssertEqual(parts("  Done.  "), ["Done.", nil])
        XCTAssertEqual(parts("模型未能加载，请重试；若仍失败，请切换模型"), ["模型未能加载，请重试；若仍失败，请切换模型", nil])
        XCTAssertEqual(parts("Version 1.2 failed to load"), ["Version 1.2 failed to load", nil], "A period inside a word is not a sentence end")
    }

    func testRealPanelFrameMatchesTheNoticeAndStaysOnScreen() throws {
        _ = NSApplication.shared
        for language in [UILanguage.chinese, .english] {
            Loc.use(language)
            let appState = state(unconfirmed())
            let panel = OverlayPanel()
            panel.show(appState: appState, targetApp: nil, onCancel: {}, onConfirm: {}, onCopy: {}, onRecover: {}, onDismiss: {})
            defer { panel.hide() }
            let frame = try XCTUnwrap(panel.windowFrame)
            XCTAssertEqual(frame.size, OverlayLayout(appState: appState).panelSize)
            if let visible = NSScreen.main?.visibleFrame {
                XCTAssertTrue(visible.contains(frame), "\(frame) must lie inside \(visible)")
            }
        }
    }
}
