import Foundation
import XCTest
@testable import UtterRuntime

final class CallbackTasksTests: XCTestCase {
    @MainActor
    func testDrainFinishesAcceptedCallbacksWithoutCancellationAndKeepsTheGateOpen() async {
        let owner = CallbackTasks()
        let gate = CallbackGate()
        var calls = 0
        owner.enqueue {
            await gate.wait()
            XCTAssertFalse(Task.isCancelled)
            calls += 1
        }
        while !(await gate.isWaiting) { await Task.yield() }
        var drained = false
        let drain = Task { await owner.drain(); drained = true }
        owner.enqueue { calls += 1 }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(drained)
        await gate.release()
        await drain.value
        XCTAssertEqual(calls, 2)
        owner.enqueue { calls += 1 }
        await owner.drain()
        XCTAssertEqual(calls, 3)
        await owner.close()
    }

    @MainActor
    func testCloseDrainsAnAlreadyAdmittedNonCooperativeCallbackAndRejectsLaterOnes() async {
        let owner = CallbackTasks()
        let gate = CallbackGate()
        var entered = false
        var finished = false
        var lateCallbackRan = false
        owner.enqueue {
            entered = true
            await withTaskCancellationHandler {
                await gate.wait()
            } onCancel: {
                Task { await gate.recordCancellation() }
            }
            finished = true
        }
        while !entered { await Task.yield() }
        while !(await gate.isWaiting) { await Task.yield() }
        var closed = false
        let closer = Task { await owner.close(); closed = true }
        while !(await gate.wasCancelled) { await Task.yield() }
        owner.enqueue { lateCallbackRan = true }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(closed)
        XCTAssertFalse(finished)
        await gate.release()
        await closer.value
        XCTAssertTrue(finished)
        XCTAssertTrue(closed)
        XCTAssertFalse(lateCallbackRan)
        await owner.close()
    }

    @MainActor
    func testRevokedQueuedCallbackDoesNotObserveOrMutateProductState() async {
        let owner = CallbackTasks()
        var touched = false
        owner.enqueue { touched = true }
        owner.revoke()
        await owner.close()
        XCTAssertFalse(touched)
    }
}

private actor CallbackGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var wasCancelled = false
    var isWaiting: Bool { continuation != nil }
    func recordCancellation() { wasCancelled = true }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
