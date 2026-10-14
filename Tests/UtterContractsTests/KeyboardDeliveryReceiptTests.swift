import XCTest
import UtterContracts

final class KeyboardDeliveryReceiptTests: XCTestCase {
    func testConfirmedKeyboardInsertionNeedsNoDesktopAnchor() {
        let operationID = UUID()
        let receipt = DeliveryReceipt(operationID: operationID, disposition: .accepted,
            effect: .keyboardInsertion, confirmation: .targetValue)
        XCTAssertEqual(receipt.operationID, operationID)
        XCTAssertEqual(receipt.disposition, .accepted)
        XCTAssertEqual(receipt.effect, .keyboardInsertion)
        XCTAssertEqual(receipt.effects, [.keyboardInsertion])
        XCTAssertEqual(receipt.confirmation, .targetValue)
        XCTAssertEqual(receipt.status, .inserted)
        XCTAssertTrue(receipt.isConfirmedInsertion)
        XCTAssertNil(receipt.anchor)
        XCTAssertNil(receipt.selectionEdit)
    }

    func testKeyboardEffectWithoutConfirmedReadbackRemainsUncertain() {
        for disposition in [DeliveryDisposition.accepted, .uncertain, .notCommitted] {
            let receipt = DeliveryReceipt(operationID: UUID(), disposition: disposition,
                effect: .keyboardInsertion)
            XCTAssertEqual(receipt.disposition, .uncertain)
            XCTAssertEqual(receipt.status, .uncertain)
            XCTAssertEqual(receipt.confirmation, .none)
            XCTAssertFalse(receipt.isConfirmedInsertion)
        }
        let partial = DeliveryReceipt(operationID: UUID(), disposition: .uncertain,
            effect: .keyboardInsertion, confirmation: .targetValue)
        XCTAssertEqual(partial.status, .uncertain)
        XCTAssertEqual(partial.confirmation, .none)
        let wrong = DeliveryReceipt(operationID: UUID(), disposition: .accepted,
            effect: .keyboardInsertion, confirmation: .clipboardValue)
        XCTAssertEqual(wrong.status, .uncertain)
    }

    func testNoEffectCannotBecomeConfirmedAndKeyboardPrecedesClipboard() {
        let absent = DeliveryReceipt(operationID: UUID(), disposition: .accepted,
            effect: .none, confirmation: .targetValue)
        XCTAssertEqual(absent.disposition, .notCommitted)
        XCTAssertEqual(absent.status, .notDelivered)
        let combined = DeliveryReceipt(operationID: UUID(), disposition: .accepted,
            effect: .clipboard, effects: [.clipboard, .keyboardInsertion], confirmation: .targetValue)
        XCTAssertEqual(combined.effect, .keyboardInsertion)
        XCTAssertEqual(combined.status, .inserted)
    }
}
