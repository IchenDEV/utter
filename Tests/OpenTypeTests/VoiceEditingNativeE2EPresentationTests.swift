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
    func testRealCompiledSessionAndNativeReviewPointerApplyCancel() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let frontmostBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let generalChangeBefore = NSPasteboard.general.changeCount
        let original = "  中文 e\u{301} 👩🏽‍💻 🇸🇬\n" + String(repeating: "保留完整选区与空白。\n", count: 80) + "\n  "
        let candidate = ("请您同步进展。 e\u{301} 👩🏽‍💻\n" + String(repeating: "候选细节保持完整。\n", count: 80))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for apply in [false, true] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.target.selectedText = original
            fixture.recipe.generatedText = candidate
            try await fixture.start()
            let execution = try fixture.runtime.service(SessionServices.execution)
            let outputs = try fixture.runtime.service(SessionServices.outputs)
            let settings = try fixture.runtime.service(DataServices.settings)
            let credentials = try fixture.runtime.service(DataServices.credentials)
            let overlay = NativeOverlayPresentation(screen: nil)
            let host = NativeDesktopHost(catalog: PresentationRegistry(), settings: settings,
                credentials: credentials, execution: execution, outputs: outputs, overlay: overlay,
                icons: nil, diagnostics: NativeE2EDiagnostics(), isCurrent: { true })
            defer { host.close() }
            Loc.use(.english)
            let intent = SessionIntent(input: .text("改礼貌一点并保留全部细节"), mode: .command)
            try execution.start(intent)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while execution.snapshot.selectionEditProposal == nil, execution.snapshot.isBusy,
                  ContinuousClock.now < deadline { await Task.yield() }
            let proposal = try XCTUnwrap(execution.snapshot.selectionEditProposal)
            XCTAssertEqual(proposal.originalSelection, original)
            XCTAssertEqual(proposal.candidate, candidate)
            XCTAssertEqual(proposal.recognizedInstruction, "改礼貌一点并保留全部细节")
            XCTAssertTrue(fixture.output.requests.isEmpty)
            XCTAssertTrue(fixture.capture.requests.isEmpty)
            XCTAssertTrue(fixture.screen.requests.isEmpty)
            host.state.project(execution.snapshot)
            overlay.show(context: host.context, targetApp: nil)
            let panel = try NativeE2EUI.panel()
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                panel.appearance = NSAppearance(named: appearance)
                try await NativeE2EUI.capture("review-\(apply)-\(appearance.rawValue)", window: panel)
            }
            XCTAssertFalse(panel.isKeyWindow)
            XCTAssertFalse(host.applySelectionEdit(sessionID: UUID(), proposalID: proposal.id))
            XCTAssertFalse(host.applySelectionEdit(sessionID: intent.id, proposalID: UUID()))
            try NativeE2EUI.localKey(36, character: "\r", in: panel)
            XCTAssertTrue(fixture.output.requests.isEmpty)
            XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeBefore)
            try await NativeE2EUI.pointer(apply ? L("selection_edit.apply") : L("common.cancel"), in: panel)
            let pointerDeadline = ContinuousClock.now.advanced(by: .seconds(3))
            while execution.snapshot.selectionEditProposal != nil, execution.snapshot.isBusy,
                  ContinuousClock.now < pointerDeadline { try await Task.sleep(for: .milliseconds(20)) }
            if execution.snapshot.selectionEditProposal != nil {
                execution.cancel(intent.id)
                try? await fixture.runtime.stop()
                return XCTFail("Process-local pointer did not dispatch the native control; no host action attempted")
            }
            if apply {
                _ = try await execution.waitForCompletion(intent.id)
                XCTAssertEqual(fixture.output.requests.count, 1)
                guard case .replaceSelection(let written) = fixture.output.requests.first?.command else {
                    return XCTFail("Native pointer did not authorize selected replacement")
                }
                XCTAssertEqual(written, candidate)
                XCTAssertFalse(host.applySelectionEdit(sessionID: intent.id, proposalID: proposal.id))
            } else {
                do { _ = try await execution.waitForCompletion(intent.id); XCTFail("Cancel accepted") }
                catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertTrue(fixture.output.requests.isEmpty)
            }
            XCTAssertEqual(fixture.target.selectedText, original, "This fixture target never writes a host document")
            XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeBefore)
            try NativeE2EUI.record("session-native-pointer-\(apply)", ["sessionID": intent.id.uuidString,
                "proposalID": proposal.id.uuidString, "originalUTF16": original.utf16.count,
                "candidateUTF16": candidate.utf16.count, "outputRequests": fixture.output.requests.count,
                "targetAndOutput": "controlled existing Workflow fixtures; no external host",
                "pointer": "process-local NSEvent through actual native NSPanel; not system pointer",
                "sessionAndPresentation": "real SwiftPM owner modules and resources"])
            overlay.hide()
            try await fixture.runtime.stop()
        }
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmostBefore)
        XCTAssertFalse(NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.nonactivatingPanel) })
    }
}
