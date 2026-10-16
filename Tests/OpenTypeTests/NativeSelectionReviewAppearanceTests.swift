import AppKit
import SwiftUI
import XCTest
import UtterContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
final class NativeSelectionReviewAppearanceTests: XCTestCase {
    private typealias UI = NativeSelectionReviewTestSupport

    func testAutomaticEditHUDUsesOriginalControlsAndNeverShowsOriginalCandidateOrApply() async throws {
        let language: UILanguage = L("common.cancel") == "Cancel" ? .english : .chinese
        defer { Loc.use(language) }
        for locale in [UILanguage.english, .chinese] {
            Loc.use(locale)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let owner = OverlayPanel()
                defer { owner.hide() }
                let state = AppState()
                state.project(SessionExecutionSnapshot(phase: .recording, transcript: "今天确认三件事。", isBusy: true))
                let recording = try await show(owner, state: state)
                recording.appearance = NSAppearance(named: appearance)
                try await UI.settle(recording)
                let cancelSize = try UI.button(L("overlay.cancel_recording"), in: recording).accessibilityFrame().size
                try await NativeE2EUI.capture("original-recording-\(locale)-\(appearance.rawValue)", window: recording)
                owner.hide()
                let secret = "SECRET-ORIGINAL-" + String(repeating: "长文本 👩🏽‍💻\n", count: 500)
                let result = "SECRET-CANDIDATE-" + String(repeating: "修改结果 🇸🇬\n", count: 500)
                state.project(SessionExecutionSnapshot(id: UUID(), phase: .processing,
                    transcript: secret, text: result, isBusy: true, isSelectionEditing: true))
                state.selectionEditCancelShortcut = true
                let layout = OverlayLayout(appState: state)
                XCTAssertEqual(layout.width, 216)
                XCTAssertEqual(layout.height, 40)
                let panel = try await show(owner, state: state)
                panel.appearance = NSAppearance(named: appearance)
                try await UI.settle(panel)
                XCTAssertEqual(panel.frame.size, layout.panelSize)
                let cancel = try UI.button(L("common.cancel"), in: panel)
                XCTAssertEqual(cancel.accessibilityFrame().size, cancelSize)
                XCTAssertEqual(cancelSize.width, 26, accuracy: 1)
                UI.assertVisible(cancel, in: panel)
                let labels = UI.nodes(panel).map { ($0.accessibilityLabel() ?? "") + $0.textValue }
                XCTAssertFalse(labels.contains { $0.contains("SECRET-ORIGINAL-") || $0.contains("SECRET-CANDIDATE-") })
                XCTAssertFalse(UI.nodes(panel).contains { $0.accessibilityRole() == .button && $0.accessibilityLabel() == L("selection_edit.apply") })
                XCTAssertFalse(panel.isKeyWindow)
                try await NativeE2EUI.capture("automatic-processing-\(locale)-\(appearance.rawValue)", window: panel)
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
