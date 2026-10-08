import XCTest
import UtterContracts
@testable import UtterMacServices

@MainActor
final class TextDeliveryTransactionTests: XCTestCase {
    func testDirectRangeWriteHasNoClipboardOrKeyboardEffects() async {
        for allowed in [false, true] {
            let target = TransactionTarget()
            let clipboard = TransactionPasteboard()
            var effects: Set<DeliveryEffect> = []
            let result = await TextDeliveryTransaction.deliver("new", target: target, pasteboard: clipboard,
                allowsClipboardPaste: allowed, isSecureInput: { false }, prepareKeys: { _ in XCTFail("AX should write directly"); return nil },
                canCommit: { true }, mark: { effects.insert($0).inserted })
            XCTAssertEqual(result.confirmation, .targetValue)
            XCTAssertEqual(effects, [.accessibility])
            XCTAssertEqual(target.writes, ["new"])
            XCTAssertEqual(clipboard.changeCount, 0)
            XCTAssertEqual(target.restorations, 0)
        }
    }

    func testPossiblyPartialAXFailureNeverRetriesUsingClipboard() async {
        let target = TransactionTarget()
        target.writeSucceeds = false
        let clipboard = TransactionPasteboard()
        var effects: Set<DeliveryEffect> = []
        let result = await TextDeliveryTransaction.deliver("new", target: target, pasteboard: clipboard,
            allowsClipboardPaste: true, isSecureInput: { false }, prepareKeys: { _ in XCTFail("No retry after AX write"); return nil },
            canCommit: { true }, mark: { effects.insert($0).inserted })
        XCTAssertEqual(result.disposition, .uncertain)
        XCTAssertEqual(target.writes.count, 1)
        XCTAssertEqual(clipboard.changeCount, 0)
        XCTAssertEqual(effects, [.accessibility])
    }

    func testDisabledPasteCannotWriteTheClipboardEvenUnderSecureInput() async {
        for secure in [false, true] {
            let target = TransactionTarget()
            target.supportsSelectionWrite = false
            let clipboard = TransactionPasteboard()
            var effects: Set<DeliveryEffect> = []
            let result = await TextDeliveryTransaction.deliver("new", target: target, pasteboard: clipboard,
                allowsClipboardPaste: false, isSecureInput: { secure }, prepareKeys: { _ in XCTFail("Keys are disabled"); return nil },
                canCommit: { true }, mark: { effects.insert($0).inserted })
            XCTAssertEqual(result.disposition, .notCommitted)
            XCTAssertEqual(result.confirmation, .none)
            XCTAssertTrue(effects.isEmpty)
            XCTAssertEqual(clipboard.text, "old")
            XCTAssertEqual(clipboard.changeCount, 0)
            XCTAssertEqual(target.restorations, 1)
        }
    }

    func testEnabledClipboardFallbackCanCopyUnderSecureInputWithoutPostingKeys() async {
        let target = TransactionTarget()
        target.supportsSelectionWrite = false
        let clipboard = TransactionPasteboard()
        var effects: Set<DeliveryEffect> = []
        let result = await TextDeliveryTransaction.deliver("new", target: target, pasteboard: clipboard,
            allowsClipboardPaste: true, isSecureInput: { true }, prepareKeys: { _ in XCTFail("Secure input blocks keys"); return nil },
            canCommit: { true }, mark: { effects.insert($0).inserted })
        XCTAssertEqual(result.confirmation, .clipboardValue)
        XCTAssertEqual(effects, [.clipboard])
        XCTAssertEqual(clipboard.text, "new")
    }

    func testTargetChangeDuringSelectionPreparationCommitsNothing() async {
        let target = TransactionTarget()
        target.changesDuringPreparation = true
        let result = await TextDeliveryTransaction.deliver("new", target: target, pasteboard: TransactionPasteboard(),
            allowsClipboardPaste: true, isSecureInput: { false }, prepareKeys: { _ in XCTFail(); return nil },
            canCommit: { true }, mark: { _ in XCTFail("Stale target"); return false })
        XCTAssertEqual(result.disposition, .notCommitted)
        XCTAssertTrue(target.writes.isEmpty)
    }

    func testDeleteUsesOneKeyEffectAndRequiresObservedTargetValue() async {
        let target = TransactionTarget()
        target.supportsSelectionWrite = false
        target.confirmed = false
        var effects: Set<DeliveryEffect> = []
        var posts = 0
        let result = await TextDeliveryTransaction.deliver("", target: target, pasteboard: TransactionPasteboard(),
            allowsClipboardPaste: true, isSecureInput: { false }, prepareKeys: { deleting in
                XCTAssertTrue(deleting); return { posts += 1; return true }
            }, canCommit: { true }, mark: { effects.insert($0).inserted })
        XCTAssertEqual(effects, [.keyPress])
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(result.disposition, .uncertain)
        XCTAssertEqual(result.confirmation, .none)
    }
}

@MainActor
private final class TransactionTarget: DeliveryTextTarget {
    var isCurrent = true
    var supportsSelectionWrite = true
    var changesDuringPreparation = false
    var writeSucceeds = true
    var confirmed = true
    var writes: [String] = []
    var restorations = 0
    func prepareSelection() -> Bool { if changesDuringPreparation { isCurrent = false }; return true }
    func writeSelection(_ text: String) -> Bool { writes.append(text); return writeSucceeds }
    func confirm(_ text: String) async -> Bool { confirmed }
    func restoreSelection() { restorations += 1 }
}

@MainActor
private final class TransactionPasteboard: DeliveryPasteboard {
    var changeCount = 0
    var text: String? = "old"
    func snapshot() -> [[String: Data]] { [] }
    func write(_ text: String) -> Bool { self.text = text; changeCount += 1; return true }
    func restore(_ items: [[String: Data]]) { changeCount += 1 }
}
