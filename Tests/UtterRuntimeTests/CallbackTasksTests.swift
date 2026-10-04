import Foundation
import XCTest
@testable import UtterRuntime

final class CallbackTasksTests: XCTestCase {
    @MainActor
    func testCloseDrainsAnAlreadyAdmittedNonCooperativeCallbackAndRejectsLaterOnes() async {
        let owner = CallbackTasks()
        let gate = CallbackGate()
        var entered = false
        var finished = false
        var lateCallbackRan = false
        owner.enqueue {
            entered = true
            await gate.wait()
            finished = true
        }
        while !entered { await Task.yield() }
        var closed = false
        let closer = Task { await owner.close(); closed = true }
        await Task.yield()
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
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
