import Foundation
import XCTest
@testable import UtterRuntime

final class BoundedWaitTests: XCTestCase {
    private struct Injected: Error {}

    private actor Sleeper {
        private(set) var started = false
        private(set) var cancelled = false

        func sleepUntilCancelled() async throws {
            started = true
            do { try await Task.sleep(for: .seconds(3600)) }
            catch { cancelled = true; throw error }
        }
    }

    @MainActor
    private final class Stall {
        private var continuation: CheckedContinuation<Void, Never>?
        var isWaiting: Bool { continuation != nil }

        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() { continuation?.resume(); continuation = nil }
    }

    private func name(_ outcome: BoundedWaitOutcome) -> String {
        switch outcome {
        case .finished: "finished"
        case .failed: "failed"
        case .timedOut: "timedOut"
        }
    }

    @MainActor
    func testFinishedOperationIsNotGatedByTheTimer() async {
        let sleeper = Sleeper()
        let outcome = await BoundedWait.run(limit: .seconds(3600), sleep: { _ in try await sleeper.sleepUntilCancelled() }) {}
        XCTAssertEqual(name(outcome), "finished")
        await waitUntil { await sleeper.cancelled }
        let cancelled = await sleeper.cancelled
        XCTAssertTrue(cancelled, "The timer must be cancelled once the operation wins")
    }

    @MainActor
    func testThrownErrorIsReportedAndNotTreatedAsTimeout() async throws {
        let sleeper = Sleeper()
        let outcome = await BoundedWait.run(limit: .seconds(3600), sleep: { _ in try await sleeper.sleepUntilCancelled() }) {
            throw Injected()
        }
        guard case let .failed(error) = outcome else { return XCTFail("Expected failure, got \(name(outcome))") }
        XCTAssertTrue(error is Injected)
    }

    @MainActor
    func testStalledOperationTimesOutAndALateCompletionIsInert() async {
        let stall = Stall()
        let outcome = await BoundedWait.run(limit: .seconds(5), sleep: { _ in }) { await stall.wait() }
        XCTAssertEqual(name(outcome), "timedOut")
        await waitUntil { stall.isWaiting }
        stall.release()
        for _ in 0..<10 { await Task.yield() }
    }

    @MainActor
    func testTimeoutCancelsACooperativeOperation() async {
        let sleeper = Sleeper()
        let outcome = await BoundedWait.run(limit: .seconds(5), sleep: { _ in }) {
            try await sleeper.sleepUntilCancelled()
        }
        XCTAssertEqual(name(outcome), "timedOut")
        await waitUntil { await sleeper.cancelled }
        let cancelled = await sleeper.cancelled
        XCTAssertTrue(cancelled, "The abandoned worker should be asked to cancel")
    }

    @MainActor
    func testRealClockBoundsAStall() async {
        let stall = Stall()
        let started = ContinuousClock.now
        let outcome = await BoundedWait.run(limit: .milliseconds(100)) { await stall.wait() }
        XCTAssertEqual(name(outcome), "timedOut")
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
        stall.release()
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
