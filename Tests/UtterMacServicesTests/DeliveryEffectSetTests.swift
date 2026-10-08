import XCTest
import UtterContracts
@testable import UtterMacServices

@MainActor
final class DeliveryEffectSetTests: XCTestCase {
    func testAcceptedWithoutEvidenceOrWithWrongEvidenceBecomesUncertain() async throws {
        let unknown = DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste)
        XCTAssertEqual(unknown.status, .uncertain)
        let wrong = DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .clipboard, confirmation: .targetValue)
        XCTAssertEqual(wrong.status, .uncertain)
        let copiedAfterPaste = DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste,
            effects: [.clipboard, .paste], confirmation: .clipboardValue)
        XCTAssertEqual(copiedAfterPaste.status, .uncertain)
        let absent = DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .none, confirmation: .targetValue)
        XCTAssertEqual(absent.status, .notDelivered)
    }

    func testClipboardAndPasteAreSeparateEffectsAndNeitherCanReplay() async throws {
        let service = ScopedOutputService(isCurrent: { true }) { _, _, mark in
            XCTAssertTrue(mark(.clipboard))
            XCTAssertFalse(mark(.clipboard))
            XCTAssertTrue(mark(.paste))
            XCTAssertFalse(mark(.paste))
            return DeliveryCompletion(disposition: .accepted, confirmation: .targetValue)
        }
        let delivery = try service.prepare(DeliveryRequest(id: UUID(), command: .insert("fixture")), isSessionCurrent: { true })
        let receipt = await delivery.commit()
        XCTAssertEqual(receipt.effects, [.clipboard, .paste])
        XCTAssertEqual(receipt.confirmation, .targetValue)
        XCTAssertTrue(receipt.isConfirmedInsertion)
        await service.close()
    }

    func testClipboardMutationBeforeCancellationCannotBeReportedAsNoSideEffect() async throws {
        var current = true
        let service = ScopedOutputService(isCurrent: { true }) { _, _, mark in
            XCTAssertTrue(mark(.clipboard))
            current = false
            XCTAssertFalse(mark(.paste))
            return DeliveryCompletion(disposition: .notCommitted)
        }
        let delivery = try service.prepare(DeliveryRequest(id: UUID(), command: .insert("fixture")), isSessionCurrent: { current })
        let receipt = await delivery.commit()
        XCTAssertEqual(receipt.disposition, .uncertain)
        XCTAssertEqual(receipt.effects, [.clipboard])
        XCTAssertFalse(receipt.isConfirmedInsertion)
        await service.close()
    }

    func testCopyAndUnconfirmedPasteCannotCreateInsertionAnchors() async throws {
        let service = ScopedOutputService(isCurrent: { true }) { _, _, mark in
            XCTAssertTrue(mark(.clipboard))
            return DeliveryCompletion(disposition: .accepted, confirmation: .clipboardValue)
        }
        let request = DeliveryRequest(id: UUID(), command: .clipboard("fixture"))
        let delivery = try service.prepare(request, isSessionCurrent: { true })
        let receipt = await delivery.commit()
        XCTAssertEqual(receipt.disposition, .accepted)
        XCTAssertFalse(receipt.isConfirmedInsertion)
        XCTAssertNil(receipt.anchor)
        await service.close()
    }
}
