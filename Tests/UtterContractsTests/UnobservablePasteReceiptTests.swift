import XCTest
import UtterContracts

final class UnobservablePasteReceiptTests: XCTestCase {
    func testAPostedPasteThatCannotBeObservedIsAcceptedButNeverInserted() {
        let receipt = DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .none,
            effects: [.clipboard, .paste], confirmation: .unobservable)
        XCTAssertEqual(receipt.disposition, .accepted)
        XCTAssertEqual(receipt.confirmation, .unobservable)
        XCTAssertEqual(receipt.status, .uncertain)
        XCTAssertFalse(receipt.isConfirmedInsertion)
        XCTAssertNil(receipt.anchor)
        XCTAssertNil(receipt.selectionEdit)
    }

    func testUnobservableNeedsAPostedPasteAndAnEffect() {
        let clipboardOnly = DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .clipboard,
            confirmation: .unobservable)
        XCTAssertEqual(clipboardOnly.disposition, .uncertain)
        XCTAssertEqual(clipboardOnly.confirmation, .none)
        XCTAssertEqual(clipboardOnly.status, .uncertain)
        let nothing = DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .none,
            confirmation: .unobservable)
        XCTAssertEqual(nothing.disposition, .notCommitted)
        XCTAssertEqual(nothing.status, .notDelivered)
    }

    func testUnobservableIsOnlyKeptWhileAccepted() {
        let uncertain = DeliveryReceipt(operationID: UUID(), disposition: .uncertain, effect: .none,
            effects: [.clipboard, .paste], confirmation: .unobservable)
        XCTAssertEqual(uncertain.disposition, .uncertain)
        XCTAssertEqual(uncertain.confirmation, .none)
    }

    func testCompatibilityPasteRequiresClipboardPasteInTheRequest() {
        XCTAssertFalse(DeliveryRequest(id: UUID(), command: .insert("x")).allowsOpaquePaste)
        XCTAssertTrue(DeliveryRequest(id: UUID(), command: .insert("x"), allowsOpaquePaste: true).allowsOpaquePaste)
        XCTAssertFalse(DeliveryRequest(id: UUID(), command: .insert("x"), allowsClipboardPaste: false,
                                       allowsOpaquePaste: true).allowsOpaquePaste)
    }
}
