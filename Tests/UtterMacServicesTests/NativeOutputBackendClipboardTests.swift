#if os(macOS)
import AppKit
import XCTest
import UtterContracts
@testable import UtterMacServices

@MainActor
final class NativeOutputBackendClipboardTests: XCTestCase {
    func testMissingTargetRespectsDisabledAutomaticClipboardAndKeepsTheDefaultFallback() async throws {
        for allowed in [false, true] {
            let pasteboard = NSPasteboard(name: .init("UtterOutput-" + UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString("original", forType: .string))
            let count = pasteboard.changeCount
            var effects: Set<DeliveryEffect> = []
            let backend = NativeOutputBackend(log: Log(service: ClipboardDiagnostics()), isCurrent: { true }, pasteboard: pasteboard)
            let result = await backend.deliver(DeliveryRequest(id: UUID(), command: .insert("candidate"), allowsClipboardPaste: allowed),
                canCommit: { true }, markCommitted: { effects.insert($0).inserted })
            XCTAssertEqual(result.disposition, allowed ? .accepted : .notCommitted)
            XCTAssertEqual(result.confirmation, allowed ? .clipboardValue : .none)
            XCTAssertEqual(pasteboard.string(forType: .string), allowed ? "candidate" : "original")
            if allowed { XCTAssertEqual(effects, [.clipboard]) }
            else { XCTAssertTrue(effects.isEmpty); XCTAssertEqual(pasteboard.changeCount, count) }
        }
    }

    func testExplicitCopyStillWorksWhenAutomaticClipboardIsDisabled() async {
        let pasteboard = NSPasteboard(name: .init("UtterExplicitCopy-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let backend = NativeOutputBackend(log: Log(service: ClipboardDiagnostics()), isCurrent: { true }, pasteboard: pasteboard)
        var effects: Set<DeliveryEffect> = []
        let result = await backend.deliver(DeliveryRequest(id: UUID(), command: .clipboard("chosen"), allowsClipboardPaste: false),
            canCommit: { true }, markCommitted: { effects.insert($0).inserted })
        XCTAssertEqual(result.confirmation, .clipboardValue)
        XCTAssertEqual(pasteboard.string(forType: .string), "chosen")
        XCTAssertEqual(effects, [.clipboard])
    }
}
private struct ClipboardDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
#endif
