import Foundation
import XCTest
import UtterContracts
@testable import UtterModels

final class BorrowedModelAccessTests: XCTestCase {
    func testParentCannotReleaseWhileBorrowedChildIsStillUsingModel() async throws {
        let gate = LocalModelAccessGate()
        let latch = BorrowedAccessLatch()
        let parent = Task {
            try await gate.withAccess {
                let borrowed = gate.inheritingCurrentAccess()
                let child = Task.detached { try await borrowed.withAccess { await latch.hold() } }
                while !(await latch.entered) { await Task.yield() }
                return child
            }
        }
        while !(await latch.entered) { await Task.yield() }
        let maintenance = Task { try await gate.withAccess { "maintained" } }
        while await gate.waitingTaskCount == 0 { await Task.yield() }
        let released = await latch.isReleased()
        XCTAssertFalse(released)
        await latch.release()
        let child = try await parent.value
        try await child.value
        let outcome = try await maintenance.value
        XCTAssertEqual(outcome, "maintained")
        await gate.close()
    }
    func testDetachedChildCanUseParentLeaseWithoutWaitingForParentToRelease() async throws {
        let gate = LocalModelAccessGate()
        let value = try await gate.withAccess {
            let borrowed = gate.inheritingCurrentAccess()
            return try await Task.detached { try await borrowed.withAccess { 42 } }.value
        }
        XCTAssertEqual(value, 42)
        let waiters = await gate.waitingTaskCount
        XCTAssertEqual(waiters, 0)
        await gate.close()
    }

    func testRetainedLeaseCannotEnterAfterParentCompletesOrJoinAnotherSession() async throws {
        let gate = LocalModelAccessGate()
        let borrowed = try await gate.withAccess { gate.inheritingCurrentAccess() }
        do { _ = try await borrowed.withAccess { "stale" }; XCTFail("Retired lease was reused") }
        catch { XCTAssertEqual(error as? ModelResourceError, .closed) }
        try await gate.withAccess {
            do { _ = try await borrowed.withAccess { "next session" }; XCTFail("Retired lease entered a new owner") }
            catch { XCTAssertEqual(error as? ModelResourceError, .closed) }
        }
        await gate.close()
    }
}

private actor BorrowedAccessLatch {
    private(set) var entered = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func hold() async { entered = true; await withCheckedContinuation { waiter = $0 } }
    func release() { released = true; waiter?.resume(); waiter = nil }
    func isReleased() -> Bool { released }
}
