import AppKit
import ApplicationServices
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterRuntime
@testable import UtterMacServices

@MainActor
final class VoiceEditingNativeE2ESafetyTests: XCTestCase {
    func testSecureInputRefusesDirectSelectionWriteBeforeAndAfterPreparation() async {
        for initiallySecure in [true, false] {
            let target = NativeE2ETransactionTarget()
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.setString("task-owned clipboard sentinel", forType: .string)
            let before = board.changeCount
            var secure = initiallySecure
            target.onPrepare = { secure = true }
            var effects: [DeliveryEffect] = []
            let result = await TextDeliveryTransaction.deliver("synthetic revised selection", target: target,
                pasteboard: NativeDeliveryPasteboard(board), allowsClipboardPaste: false,
                isSecureInput: { secure }, prepareKeys: { _ in XCTFail("No keyboard effects allowed"); return nil },
                canCommit: { true }, mark: { effects.append($0); return true })
            XCTAssertEqual(result.disposition, .notCommitted, "Secure input must refuse the direct AX branch")
            XCTAssertTrue(target.writes.isEmpty, "Direct AX selection write occurred under secure input")
            XCTAssertTrue(effects.isEmpty)
            XCTAssertEqual(target.preparations, initiallySecure ? 0 : 1)
            if initiallySecure { XCTAssertEqual(target.currentChecks, 0) }
            XCTAssertEqual(target.restorations, 0)
            XCTAssertEqual(board.changeCount, before)
            XCTAssertEqual(board.string(forType: .string), "task-owned clipboard sentinel")
        }
    }

    func testSecureInputEnabledByEffectAdmissionCannotWriteOrFallBack() async {
        let target = NativeE2ETransactionTarget()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("owned sentinel", forType: .string)
        let before = board.changeCount
        var secure = false
        let result = await TextDeliveryTransaction.deliver("replacement", target: target,
            pasteboard: NativeDeliveryPasteboard(board), allowsClipboardPaste: true,
            isSecureInput: { secure }, prepareKeys: { _ in XCTFail("No fallback"); return nil },
            canCommit: { true }, mark: { _ in secure = true; return true })
        XCTAssertEqual(result.disposition, .notCommitted)
        XCTAssertTrue(target.writes.isEmpty)
        XCTAssertEqual(target.restorations, 0)
        XCTAssertEqual(board.changeCount, before)
        XCTAssertEqual(board.string(forType: .string), "owned sentinel")
    }

    func testActualNativeTargetRefusesCurrentSecureInputWithoutHostCapture() async throws {
        guard NativeDeliveryKeys.isSecureInput else {
            throw XCTSkip("Secure input is off; reading an unowned focused host is outside this probe")
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([MacPlugins.target()]))
        try await runtime.start([PluginSelection("mac.target")])
        let target = try runtime.service(MacServices.target)
        XCTAssertThrowsError(try target.capture(TargetCaptureRequest(outputMode: .command,
            inputLanguage: .english, source: .menuBar))) {
            XCTAssertEqual($0 as? DeliveryError, .invalidTarget)
        }
        let lease = NativeTargetLease(processIdentifier: ProcessInfo.processInfo.processIdentifier, state: nil,
            context: InputContext(outputMode: .command, inputLanguage: .english, source: .menuBar),
            isCurrent: { XCTFail("Secure input must refuse before owner validation"); return true })
        XCTAssertFalse(lease.isCurrent)
        XCTAssertNil(NativeDeliveryTarget(lease: NativeE2ESecureLease(), anchor: nil, requiresSelection: false))
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        XCTAssertNil(AXTargetState.capture())
        XCTAssertNil(AXTargetState.focusedIdentity())
        XCTAssertNil(AXTargetState.value(of: element))
        XCTAssertNil(AXTargetState.range(of: element))
        XCTAssertFalse(AXTargetState.setRange(NSRange(location: 0, length: 0), of: element))
        try await runtime.stop()
    }
}

@MainActor
private final class NativeE2ESecureLease: OutputTargetLease {
    let id = UUID()
    let processIdentifier = ProcessInfo.processInfo.processIdentifier
    let context = InputContext(outputMode: .command, inputLanguage: .english, source: .menuBar)
    let isValid = true
    var isCurrent: Bool { XCTFail("Secure input must refuse before lease validation"); return true }
}

@MainActor
private final class NativeE2ETransactionTarget: DeliveryTextTarget {
    var currentChecks = 0
    var isCurrent: Bool { currentChecks += 1; return true }
    let supportsSelectionWrite = true
    let isWebContentEditor = false
    var preparations = 0
    var restorations = 0
    var onPrepare: () -> Void = {}
    var writes: [String] = []
    func prepareSelection() -> Bool { preparations += 1; onPrepare(); return true }
    func writeSelection(_ text: String) -> Bool { writes.append(text); return true }
    func confirm(_ text: String) async -> Bool { true }
    func restoreSelection() { restorations += 1 }
}
