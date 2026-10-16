import AppKit
import SwiftUI
import XCTest
import UtterContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
final class NativeSelectionReviewAppearanceTests: XCTestCase {
    private typealias UI = NativeSelectionReviewTestSupport

    func testReviewUsesTheExistingRecordingButtonGeometryAndHUDScale() async throws {
        let language: UILanguage = L("common.cancel") == "Cancel" ? .english : .chinese
        defer { Loc.use(language) }
        for locale in [UILanguage.english, .chinese] {
            Loc.use(locale)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let owner = OverlayPanel()
                defer { owner.hide() }
                let state = AppState()
                state.project(SessionExecutionSnapshot(phase: .recording, transcript: "今天确认三件事。", isBusy: true))
                let recordingLayout = OverlayLayout(appState: state)
                let recording = try await show(owner, state: state)
                recording.appearance = NSAppearance(named: appearance)
                try await UI.settle(recording)
                let cancelSize = try UI.button(L("overlay.cancel_recording"), in: recording).accessibilityFrame().size
                let confirmSize = try UI.button(L("overlay.finish_recording"), in: recording).accessibilityFrame().size
                try await NativeE2EUI.capture("original-hud-\(locale)-\(appearance.rawValue)", window: recording)
                owner.hide()

                let proposal = SelectionEditProposal(sessionID: UUID(), targetID: UUID(),
                    originalSelection: "把报告给我，今天必须发。", recognizedInstruction: "改得礼貌一点，保留今天的期限。",
                    candidate: "请您今天把报告发给我，谢谢。", expiresAt: Date().addingTimeInterval(120))
                state.project(SessionExecutionSnapshot(id: proposal.sessionID, phase: .processing,
                    isBusy: true, selectionEditProposal: proposal))
                let layout = OverlayLayout(appState: state)
                XCTAssertEqual(layout.width, recordingLayout.width)
                XCTAssertEqual(layout.width, 304)
                XCTAssertLessThanOrEqual(layout.height, 360)
                let panel = try await show(owner, state: state)
                panel.appearance = NSAppearance(named: appearance)
                try await UI.settle(panel)
                XCTAssertEqual(panel.frame.size, layout.panelSize)
                let cancel = try UI.button(L("common.cancel"), in: panel)
                let apply = try UI.button(L("selection_edit.apply"), in: panel)
                XCTAssertEqual(cancel.accessibilityFrame().size, cancelSize)
                XCTAssertEqual(apply.accessibilityFrame().size, confirmSize)
                XCTAssertEqual(confirmSize.width, 26, accuracy: 1)
                XCTAssertEqual(confirmSize.height, 26, accuracy: 1)
                XCTAssertEqual(cancel.accessibilityFrame().midY, apply.accessibilityFrame().midY, accuracy: 1)
                UI.assertVisible(cancel, in: panel)
                UI.assertVisible(apply, in: panel)
                UI.assertVisible(try UI.text(proposal.originalSelection, in: panel), in: panel)
                UI.assertVisible(try UI.text(proposal.candidate, in: panel), in: panel)
                XCTAssertFalse(panel.isKeyWindow)
                try await NativeE2EUI.capture("corrected-review-\(locale)-\(appearance.rawValue)", window: panel)
                XCTAssertTrue(try apply.accessibilityPerformPress())
                try await UI.settle(panel)
                XCTAssertEqual(panel.frame.size, layout.panelSize)
                UI.assertVisible(try UI.button(L("common.cancel"), in: panel), in: panel)
                UI.assertVisible(try UI.button(L("selection_edit.apply"), in: panel), in: panel)
                XCTAssertFalse(try UI.button(L("selection_edit.apply"), in: panel).isAccessibilityEnabled())
                UI.assertVisible(try UI.text(L("selection_edit.expired"), in: panel), in: panel)
                try await NativeE2EUI.capture("corrected-review-rejected-\(locale)-\(appearance.rawValue)", window: panel)
                owner.hide()
            }
        }
    }

    func testRemoteDisclosureKeepsExplicitOneUseConsentWithCompactControls() async throws {
        let language: UILanguage = L("common.cancel") == "Cancel" ? .english : .chinese
        defer { Loc.use(language) }
        for locale in [UILanguage.english, .chinese] {
            Loc.use(locale)
            let consent = SelectionEditRemoteConsent(selectedText: "这是将发送给所选服务的完整原文。",
                providerID: "generation.remote", providerBaseURL: "https://example.invalid/v1")
            let intentID = UUID()
            var authorized = 0
            var declined = 0
            var callbacks = SelectionReviewCallbacks.none
            callbacks.authorize = { id in XCTAssertEqual(id, intentID); authorized += 1; return false }
            callbacks.decline = { id in XCTAssertEqual(id, intentID); declined += 1 }
            let panel = try await UI.panel(RemoteDisclosureView(consent: consent, intentID: intentID,
                callbacks: callbacks), width: 280, height: 240)
            defer { panel.close() }
            UI.assertVisible(try UI.text(consent.selectedText, in: panel), in: panel)
            XCTAssertTrue(try UI.button(L("common.continue"), in: panel).accessibilityPerformPress())
            try await UI.settle(panel)
            XCTAssertEqual(panel.frame.size, NSSize(width: 280, height: 240))
            _ = try UI.button(L("common.continue"), in: panel).accessibilityPerformPress()
            XCTAssertEqual(authorized, 1)
            XCTAssertFalse(try UI.button(L("common.continue"), in: panel).isAccessibilityEnabled())
            UI.assertVisible(try UI.text(L("selection_edit.remote_failed"), in: panel), in: panel)
            try await NativeE2EUI.capture("corrected-disclosure-\(locale)", window: panel)
            XCTAssertTrue(try UI.button(L("common.cancel"), in: panel).accessibilityPerformPress())
            XCTAssertEqual(declined, 1)
            panel.close()
        }
    }

    private func show(_ owner: OverlayPanel, state: AppState) async throws -> NSWindow {
        owner.show(appState: state, targetApp: nil, onCancel: {}, onConfirm: {},
            onCopy: {}, onRecover: {}, onDismiss: {})
        let panel = try NativeE2EUI.panel()
        try await UI.activateAccessibility(in: panel)
        return panel
    }
}
