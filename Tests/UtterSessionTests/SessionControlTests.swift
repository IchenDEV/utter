import XCTest
import UtterContracts
@testable import UtterSession

@MainActor
final class SessionControlTests: XCTestCase {
    func testCancelledCaptureWaiterDrainsWithoutInventingAStop() async {
        let control = SessionControl(isCurrent: { true }, cancel: {}, update: { _, _ in })
        var entered = false
        let waiter = Task { () -> Result<Void, Error> in
            entered = true
            do { try await control.waitForStop(); return .success(()) }
            catch { return .failure(error) }
        }
        while !entered { await Task.yield() }
        waiter.cancel()
        switch await waiter.value {
        case .success: XCTFail("Cancelled capture kept waiting")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(control.isStopped)
        control.stop()
        XCTAssertTrue(control.isStopped)
    }
}
