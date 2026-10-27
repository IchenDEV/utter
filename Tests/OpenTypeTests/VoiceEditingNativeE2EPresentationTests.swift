import AppKit
import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterPresentationContracts
import UtterSession
@testable import UtterPresentation

@MainActor
final class VoiceEditingNativeE2EPresentationTests: XCTestCase {
    func testRealSessionAutomaticallyAppliesThenNativePointerRestoresOnceWithoutDisplayingContent() async throws {
        for keyboardRestore in [false, true] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            let original = "  原文 e\u{301} 👩🏽‍💻 🇸🇬\n" + String(repeating: "保留完整选区与空白。\n", count: 80)
            let candidate = ("请您今天同步进展。 👩🏽‍💻\n" + String(repeating: "保留候选细节。\n", count: 80)).trimmingCharacters(in: .whitespacesAndNewlines)
            let generation = HeldSelectionGeneration(candidate)
            fixture.recipe.selectionProcessor = generation.process
            fixture.target.selectedText = original
            let anchor = EditingAnchor(target: fixture.target, text: candidate)
            fixture.output.delivery.anchor = anchor
            try await fixture.start()
            let execution = try fixture.runtime.service(SessionServices.execution)
            let outputs = try fixture.runtime.service(SessionServices.outputs)
            let registration = TestOverlayShortcutRegistration()
            let host = try makeHost(fixture, registration: registration)
            defer { host.close() }
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let clipboard = NSPasteboard.general.changeCount
            let intent = SessionIntent(input: .text("改礼貌一点并保留全部细节"), mode: .command)
            try execution.start(intent)
            try await generation.waitUntilEntered()
            host.project(execution.snapshot)
            let panel = try NativeE2EUI.panel()
            try await NativeSelectionReviewTestSupport.activateAccessibility(in: panel)
            XCTAssertFalse(registration.keys.isEmpty)
            XCTAssertNil(execution.snapshot.selectionEditProposal)
            try await NativeE2EUI.capture("real-session-auto-processing-\(keyboardRestore)", window: panel)
            generation.release()
            let completion = try await execution.waitForCompletion(intent.id)
            XCTAssertEqual(completion.deliveryStatus, .inserted)
            XCTAssertEqual(fixture.output.requests.count, 1)
            guard case .replaceSelection(let written) = fixture.output.requests.first?.command else { return XCTFail("Missing auto replacement") }
            XCTAssertEqual(written, candidate)
            host.state.project(outputs.snapshot)
            host.project(completion)
            let restoredPanel = try NativeE2EUI.panel()
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                restoredPanel.appearance = NSAppearance(named: appearance)
                try await NativeE2EUI.capture("real-session-auto-restorable-\(keyboardRestore)-\(appearance.rawValue)", window: restoredPanel)
            }
            let nodes = NativeSelectionReviewTestSupport.nodes(restoredPanel)
            XCTAssertFalse(nodes.contains { (($0.accessibilityLabel() ?? "") + $0.textValue).contains("保留候选细节") })
            XCTAssertFalse(nodes.contains { $0.accessibilityRole() == .button && $0.accessibilityLabel() == L("selection_edit.apply") })
            XCTAssertTrue(host.state.selectionEditRestoreShortcut)
            if keyboardRestore {
                let keyID = try XCTUnwrap(registration.keys.first?.key)
                registration.press(keyID); registration.press(keyID)
            } else {
                try await NativeE2EUI.pointer(L("selection_edit.restore"), in: restoredPanel)
            }
            let restoreID = try XCTUnwrap(execution.snapshot.id)
            _ = try await execution.waitForCompletion(restoreID)
            XCTAssertEqual(fixture.output.requests.count, 2)
            guard case .replaceAnchor(let restored, _) = fixture.output.requests.last?.command else { return XCTFail("Missing receipt restore") }
            XCTAssertEqual(restored, original)
            XCTAssertFalse(host.restoreSelectionEdit(operationID: intent.id))
            XCTAssertEqual(fixture.output.requests.count, 2)
            XCTAssertNil(outputs.snapshot.selectionEditRestoration)
            XCTAssertEqual(NSPasteboard.general.changeCount, clipboard)
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmost)
            XCTAssertFalse(restoredPanel.isKeyWindow)
            host.close()
            XCTAssertTrue(registration.closed)
            try await fixture.runtime.stop()
        }
    }

    func testNativeHostScopesCancelToVisibleSessionAndDrainsLateGenerationWithoutWriting() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.target.selectedText = "原文 👩🏽‍💻"
        let generation = HeldSelectionGeneration()
        fixture.recipe.selectionProcessor = generation.process
        try await fixture.start()
        let execution = try fixture.runtime.service(SessionServices.execution)
        let registration = TestOverlayShortcutRegistration()
        let host = try makeHost(fixture, registration: registration)
        defer { host.close() }
        let intent = SessionIntent(input: .text("rewrite"), mode: .command)
        try execution.start(intent)
        try await generation.waitUntilEntered()
        host.state.project(execution.snapshot)
        host.updateShortcuts()
        XCTAssertTrue(registration.keys.isEmpty, "Hidden HUD must not intercept host Escape")
        host.showOverlay()
        let oldID = try XCTUnwrap(registration.keys.first?.key)
        host.dismissOverlay()
        XCTAssertTrue(registration.keys.isEmpty)
        registration.press(oldID)
        XCTAssertTrue(execution.snapshot.isBusy)
        host.showOverlay()
        let currentID = try XCTUnwrap(registration.keys.first?.key)
        registration.press(currentID); registration.press(currentID)
        XCTAssertTrue(registration.keys.isEmpty, "Consumed cancellation cannot re-register on the stale busy snapshot")
        generation.release()
        do { _ = try await execution.waitForCompletion(intent.id); XCTFail("Cancelled edit completed") }
        catch { XCTAssertTrue(error is CancellationError) }
        host.project(execution.snapshot)
        XCTAssertTrue(registration.keys.isEmpty)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        XCTAssertEqual(fixture.target.selectedText, "原文 👩🏽‍💻")
        host.close()
        try await fixture.runtime.stop()
    }

    private func makeHost(_ fixture: VoiceWorkflowFixture, registration: TestOverlayShortcutRegistration) throws -> NativeDesktopHost {
        NativeDesktopHost(catalog: PresentationRegistry(), settings: try fixture.runtime.service(DataServices.settings),
            credentials: try fixture.runtime.service(DataServices.credentials),
            execution: try fixture.runtime.service(SessionServices.execution), outputs: try fixture.runtime.service(SessionServices.outputs),
            overlay: NativeOverlayPresentation(screen: nil), icons: nil, diagnostics: NativeE2EDiagnostics(),
            isCurrent: { true }, shortcutRegistration: registration)
    }
}
