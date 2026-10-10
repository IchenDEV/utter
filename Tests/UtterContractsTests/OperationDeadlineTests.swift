import XCTest
import UtterContracts

final class OperationDeadlineTests: XCTestCase {
    func testTimeoutCancelsAndDrainsTheOperationBeforeReturning() async throws {
        let cleanup = DeadlineCleanup()
        do {
            let _: String = try await withOperationDeadline(for: .milliseconds(1)) {
                do { try await Task.sleep(for: .seconds(3_600)); return "late" }
                catch { await cleanup.finish(); throw error }
            }
            XCTFail("The operation must time out")
        } catch OperationDeadlineError.exceeded {}
        let finished = await cleanup.finished
        XCTAssertTrue(finished)
    }
    func testParentCancellationPropagatesAndDoesNotBecomeATimeout() async throws {
        let task = Task {
            let _: String = try await withOperationDeadline(for: .seconds(3_600)) {
                try await Task.sleep(for: .seconds(3_600))
                return "late"
            }
        }
        task.cancel()
        do { try await task.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError {}
    }
}
private actor DeadlineCleanup {
    var finished = false
    func finish() { finished = true }
}
