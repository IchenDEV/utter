import AppKit
import XCTest
import UtterContracts
import UtterData
import UtterSession
@testable import UtterPresentation

/// The desktop host is the production entry point for Copy and Apply-replacement. These tests call it
/// instead of building intents by hand, so the intent the host sends cannot drift from what is tested.
@MainActor
final class DesktopActionStartTests: XCTestCase {
    func testDesktopCopyStartsAndCopiesTheExactTextWithoutHistoryOrAnchorChange() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        fixture.output.delivery.effect = .clipboard
        fixture.output.delivery.confirmation = .clipboardValue
        let execution = try fixture.runtime.service(SessionServices.execution)
        let outputs = try fixture.runtime.service(SessionServices.outputs)
        let host = try makeHost(fixture)
        defer { host.close() }
        let recentBefore = outputs.snapshot.recentText

        host.copy("  desktop copy  ")

        let id = try XCTUnwrap(execution.snapshot.id, "The desktop copy action did not start a session")
        let result = try await execution.waitForCompletion(id)
        XCTAssertEqual(result.phase, .completed)
        XCTAssertEqual(result.deliveryStatus, .copied)
        XCTAssertEqual(fixture.output.requests.count, 1)
        guard case .clipboard(let text) = fixture.output.requests.first?.command else { return XCTFail("Copy did not use the clipboard command") }
        XCTAssertEqual(text, "  desktop copy  ")
        XCTAssertNil(fixture.output.requests.first?.target)
        XCTAssertTrue(try fixture.runtime.service(DataServices.history).records.isEmpty)
        XCTAssertEqual(outputs.snapshot.recentText, recentBefore)
        try await fixture.runtime.stop()
    }

    func testDesktopCopyOfWhitespaceStartsNothing() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let execution = try fixture.runtime.service(SessionServices.execution)
        let host = try makeHost(fixture)
        defer { host.close() }

        host.copy(" \n ")

        XCTAssertNil(execution.snapshot.id)
        XCTAssertTrue(fixture.output.requests.isEmpty)
        try await fixture.runtime.stop()
    }

    func testDesktopApplyReplacementStartsAndReplacesTheRememberedInsertion() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let (_, original) = try fixture.installPending()
        let execution = try fixture.runtime.service(SessionServices.execution)
        let history = try fixture.runtime.service(DataServices.history)
        let host = try makeHost(fixture)
        defer { host.close() }

        host.applyReplacement()

        let id = try XCTUnwrap(execution.snapshot.id, "The desktop apply-replacement action did not start a session")
        let result = try await execution.waitForCompletion(id)
        XCTAssertEqual(result.phase, .completed)
        guard case .replaceAnchor = fixture.output.requests.first?.command else { return XCTFail("Missing anchored replacement") }
        XCTAssertEqual(history.records.first(where: { $0.id == original.id })?.processedText, "Formatted text")
        try await fixture.runtime.stop()
    }

    func testDesktopApplyReplacementAfterExpiryCopiesInsteadOfReplacing() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        try await fixture.start()
        let (_, original) = try fixture.installPending(createdAt: Date().addingTimeInterval(-20))
        let execution = try fixture.runtime.service(SessionServices.execution)
        let outputs = try fixture.runtime.service(SessionServices.outputs)
        let host = try makeHost(fixture)
        defer { host.close() }

        host.applyReplacement()

        let id = try XCTUnwrap(execution.snapshot.id, "The desktop apply-replacement action did not start a session")
        _ = try await execution.waitForCompletion(id)
        guard case .clipboard(let text) = fixture.output.requests.first?.command else { return XCTFail("Expired replacement did not use explicit copy recovery") }
        XCTAssertEqual(text, "Formatted text")
        XCTAssertEqual(try fixture.runtime.service(DataServices.history).records.first?.processedText, original.processedText)
        XCTAssertEqual(outputs.snapshot.pending?.state, .copied)
        try await fixture.runtime.stop()
    }

    private func makeHost(_ fixture: VoiceWorkflowFixture) throws -> NativeDesktopHost {
        NativeDesktopHost(catalog: PresentationRegistry(), settings: try fixture.runtime.service(DataServices.settings),
            credentials: try fixture.runtime.service(DataServices.credentials),
            execution: try fixture.runtime.service(SessionServices.execution), outputs: try fixture.runtime.service(SessionServices.outputs),
            overlay: nil, icons: nil, diagnostics: NativeE2EDiagnostics(),
            isCurrent: { true }, shortcutRegistration: TestOverlayShortcutRegistration())
    }
}
