import XCTest
import UtterContracts
@testable import UtterMacServices

@MainActor
final class DeliveryReceiptTests: XCTestCase {
    private func request() -> DeliveryRequest { DeliveryRequest(id: UUID(), command: .clipboard("fixture")) }

    func testUnacknowledgedKeyboardInsertionIsConsumedWithoutRetry() async throws {
        var insertions = 0
        let service = ScopedOutputService(isCurrent: { true }) { _, _, mark in
            if mark(.keyboardInsertion) { insertions += 1 }
            return DeliveryCompletion(disposition: .accepted)
        }
        let request = DeliveryRequest(id: UUID(), command: .insert("候选 👩🏽‍💻"))
        let delivery = try service.prepare(request, isSessionCurrent: { true })
        let receipt = await delivery.commit()
        XCTAssertEqual(receipt.effects, [.keyboardInsertion])
        XCTAssertEqual(receipt.status, .uncertain)
        XCTAssertFalse(receipt.isConfirmedInsertion)
        await delivery.close()
        let replay = try service.prepare(request, isSessionCurrent: { true })
        let replayed = await replay.commit()
        XCTAssertEqual(replayed.status, .uncertain)
        XCTAssertEqual(insertions, 1)
        await service.close()
    }

    func testReplayedSelectionReceiptRetainsStatusWithoutRestorationAuthorityOrOriginalText() async throws {
        let anchor = SelectionReceiptAnchor()
        var commits = 0
        let service = ScopedOutputService(isCurrent: { true }) { request, _, mark in
            commits += 1
            XCTAssertTrue(mark(.accessibility))
            return DeliveryCompletion(disposition: .accepted, anchor: anchor, confirmation: .targetValue,
                selectionEdit: SelectionEditReceipt(operationID: request.id, originalSelection: "private original 👩🏽‍💻",
                    replacement: anchor.text, anchor: anchor))
        }
        let request = DeliveryRequest(id: UUID(), command: .replaceSelection("candidate"), target: anchor.target)
        let first = try service.prepare(request, isSessionCurrent: { true })
        let original = await first.commit()
        XCTAssertEqual(original.selectionEdit?.originalSelection, "private original 👩🏽‍💻")
        XCTAssertTrue(original.anchor === anchor)
        await first.close()
        let replay = try service.prepare(request, isSessionCurrent: { true })
        let receipt = await replay.commit()
        XCTAssertEqual(receipt.status, .inserted)
        XCTAssertNil(receipt.anchor)
        XCTAssertNil(receipt.selectionEdit)
        XCTAssertEqual(commits, 1)
        await service.close()
    }

    func testCancelledPreparationNeverCallsTheDriverOrCommits() async throws {
        var calls = 0
        let service = ScopedOutputService(isCurrent: { true }) { _, _, mark in
            calls += 1
            XCTAssertTrue(mark(.clipboard))
            return DeliveryCompletion(disposition: .accepted, confirmation: .clipboardValue)
        }
        let delivery = try service.prepare(request(), isSessionCurrent: { true })
        await delivery.close()
        let receipt = await delivery.commit()
        XCTAssertEqual(receipt.disposition, .notCommitted)
        XCTAssertEqual(receipt.effect, .none)
        XCTAssertEqual(calls, 0)
        await service.close()
    }

    func testReceiptIsIdempotentAcrossHandleCallsAndReplayedOperationIDs() async throws {
        var effects = 0
        let service = ScopedOutputService(isCurrent: { true }) { _, _, mark in
            if mark(.clipboard) { effects += 1 }
            return DeliveryCompletion(disposition: .accepted, confirmation: .clipboardValue)
        }
        let input = request()
        let first = try service.prepare(input, isSessionCurrent: { true })
        let firstReceipt = await first.commit()
        let secondReceipt = await first.commit()
        XCTAssertEqual(firstReceipt.operationID, secondReceipt.operationID)
        XCTAssertEqual(firstReceipt.disposition, .accepted)
        await first.close()
        let replay = try service.prepare(input, isSessionCurrent: { true })
        let replayed = await replay.commit()
        XCTAssertEqual(replayed.disposition, .accepted)
        XCTAssertEqual(effects, 1)
        await service.close()
    }

    func testClosedOwnerDrainsRestorationAfterCommitAndKeepsTheReceipt() async throws {
        let committed = DeliverySignal()
        let restoration = DeliverySignal()
        let closeEntered = DeliverySignal()
        let service = ScopedOutputService(isCurrent: { true }) { _, _, mark in
            XCTAssertTrue(mark(.paste))
            committed.send()
            await restoration.wait()
            return DeliveryCompletion(disposition: .accepted, confirmation: .targetValue)
        }
        let delivery = try service.prepare(request(), isSessionCurrent: { true })
        let commit = Task { await delivery.commit() }
        await committed.wait()
        var closed = false
        let close = Task {
            service.revoke()
            closeEntered.send()
            await service.close()
            closed = true
        }
        await closeEntered.wait()
        XCTAssertFalse(closed)
        XCTAssertThrowsError(try service.prepare(request(), isSessionCurrent: { true }))
        restoration.send()
        let receipt = await commit.value
        await close.value
        XCTAssertEqual(receipt.disposition, .accepted)
        XCTAssertEqual(receipt.effect, .paste)
        XCTAssertTrue(closed)
    }

    func testFailureAfterTheIrreversibleEffectIsUncertainAndNeverAutomaticallyRetried() async throws {
        var effects = 0
        let service = ScopedOutputService(isCurrent: { true }) { _, _, mark in
            if mark(.keyPress) { effects += 1 }
            return DeliveryCompletion(disposition: .notCommitted, reason: "injected failure")
        }
        let input = request()
        let delivery = try service.prepare(input, isSessionCurrent: { true })
        let receipt = await delivery.commit()
        XCTAssertEqual(receipt.disposition, .uncertain)
        await delivery.close()
        let replay = try service.prepare(input, isSessionCurrent: { true })
        let replayed = await replay.commit()
        XCTAssertEqual(replayed.disposition, .uncertain)
        XCTAssertEqual(effects, 1)
        await service.close()
    }

    func testRevokedSessionIsCheckedAfterTheDriverAwaitAndBeforeItsEffect() async throws {
        let entered = DeliverySignal()
        let resume = DeliverySignal()
        var current = true
        var effects = 0
        let service = ScopedOutputService(isCurrent: { true }) { _, canCommit, mark in
            entered.send()
            await resume.wait()
            XCTAssertFalse(canCommit())
            if mark(.paste) { effects += 1 }
            return DeliveryCompletion(disposition: .accepted, confirmation: .clipboardValue)
        }
        let delivery = try service.prepare(request(), isSessionCurrent: { current })
        let commit = Task { await delivery.commit() }
        await entered.wait()
        current = false
        resume.send()
        let receipt = await commit.value
        XCTAssertEqual(receipt.disposition, .notCommitted)
        XCTAssertEqual(effects, 0)
        await service.close()
    }
}

@MainActor
private final class SelectionReceiptAnchor: OutputAnchor {
    let target: any OutputTargetLease = SelectionReceiptTarget()
    let range = NSRange(location: 0, length: 9)
    let text = "candidate"
    let expiresAt = Date().addingTimeInterval(15)
    let isCurrent = true
    func correctionSeed(context: InputContext) -> CorrectionCaptureSeed? { nil }
}

@MainActor
private final class SelectionReceiptTarget: OutputTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 1
    let context = InputContext(outputMode: .processed, inputLanguage: .english, source: .menuBar)
    let isValid = true
    let isCurrent = true
}

@MainActor
private final class DeliverySignal {
    private var sent = false
    private var continuation: CheckedContinuation<Void, Never>?
    func send() { sent = true; continuation?.resume(); continuation = nil }
    func wait() async {
        if sent { return }
        await withCheckedContinuation { continuation = $0 }
    }
}
