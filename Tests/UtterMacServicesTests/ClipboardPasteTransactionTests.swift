import XCTest
import UtterContracts
@testable import UtterMacServices

@MainActor
final class ClipboardPasteTransactionTests: XCTestCase {
    func testSlowTargetKeepsPayloadUntilConsumptionIsConfirmed() async {
        let clipboard = FakeDeliveryPasteboard("previous")
        let result = await ClipboardPasteTransaction.paste("payload", pasteboard: clipboard,
            canCommit: { true }, mark: { _ in true }, postPaste: { true }, confirm: {
                try? await Task.sleep(for: .milliseconds(400))
                XCTAssertEqual(clipboard.text, "payload")
                return true
            })
        XCTAssertEqual(result.disposition, .accepted)
        XCTAssertEqual(result.confirmation, .targetValue)
        XCTAssertEqual(clipboard.text, "previous")
    }

    func testUnobservableOrTimedOutPasteKeepsPayloadAndNeverRetries() async {
        let clipboard = FakeDeliveryPasteboard("previous")
        var pastes = 0
        let result = await ClipboardPasteTransaction.paste("payload", pasteboard: clipboard,
            canCommit: { true }, mark: { _ in true }, postPaste: { pastes += 1; return true }, confirm: { false })
        XCTAssertEqual(result.disposition, .uncertain)
        XCTAssertEqual(clipboard.text, "payload")
        XCTAssertEqual(pastes, 1)
    }

    func testOtherClipboardChangesSurviveBothConfirmationAndPrePasteCancellation() async {
        for confirmed in [false, true] {
            let clipboard = FakeDeliveryPasteboard("previous")
            _ = await ClipboardPasteTransaction.paste("payload", pasteboard: clipboard,
                canCommit: { true }, mark: { _ in true }, postPaste: { true }, confirm: {
                    _ = clipboard.write("third-party")
                    return confirmed
                })
            XCTAssertEqual(clipboard.text, "third-party")
        }
        let clipboard = FakeDeliveryPasteboard("previous")
        var pastes = 0
        _ = await ClipboardPasteTransaction.paste("payload", pasteboard: clipboard,
            canCommit: { true }, mark: { _ in true }, postPaste: { pastes += 1; return true }, confirm: { true },
            beforePaste: { _ = clipboard.write("third-party") })
        XCTAssertEqual(clipboard.text, "third-party")
        XCTAssertEqual(pastes, 0)
    }

    func testCancellationAfterPostingDrainsObservationAndDoesNotRestoreUnconsumedText() async {
        let clipboard = FakeDeliveryPasteboard("previous")
        var posted = false
        let task = Task {
            await ClipboardPasteTransaction.paste("payload", pasteboard: clipboard,
                canCommit: { !Task.isCancelled }, mark: { _ in true }, postPaste: { posted = true; return true }, confirm: {
                    try? await Task.sleep(for: .milliseconds(30))
                    XCTAssertFalse(Task.isCancelled)
                    return false
                })
        }
        while !posted { await Task.yield() }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result.disposition, .uncertain)
        XCTAssertEqual(clipboard.text, "payload")
    }
}

@MainActor
private final class FakeDeliveryPasteboard: DeliveryPasteboard {
    var changeCount = 0
    var text: String?
    init(_ text: String) { self.text = text }
    func snapshot() -> [[String: Data]] { text.map { [["text": Data($0.utf8)]] } ?? [] }
    func write(_ text: String) -> Bool { self.text = text; changeCount += 1; return true }
    func restore(_ items: [[String: Data]]) { text = items.first?["text"].flatMap { String(data: $0, encoding: .utf8) }; changeCount += 1 }
}
