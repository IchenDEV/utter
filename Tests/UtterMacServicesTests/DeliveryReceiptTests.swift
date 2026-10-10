import XCTest
import UtterContracts
@testable import UtterMacServices

@MainActor
final class DeliveryReceiptTests: XCTestCase {
    private func request() -> DeliveryRequest { DeliveryRequest(id: UUID(), command: .clipboard("fixture")) }

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
private final class DeliverySignal {
    private var sent = false
    private var continuation: CheckedContinuation<Void, Never>?
    func send() { sent = true; continuation?.resume(); continuation = nil }
    func wait() async {
        if sent { return }
        await withCheckedContinuation { continuation = $0 }
    }
}
