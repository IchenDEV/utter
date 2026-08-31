import XCTest
@testable import OpenType

final class LocalModelAccessTests: XCTestCase {
    private actor EventRecorder {
        private var events: [String] = []

        func append(_ event: String) {
            events.append(event)
        }

        func snapshot() -> [String] {
            events
        }
    }

    func testLocalModelAccessIsReentrantWithinOneTask() async throws {
        let processor = TextProcessor()
        let recorder = EventRecorder()

        try await processor.withLocalModelAccess {
            try await processor.withLocalModelAccess {
                await recorder.append("nested")
            }
        }

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["nested"])
    }

    func testUnloadWaitsForActiveLocalModelOperation() async {
        let processor = TextProcessor()
        let recorder = EventRecorder()
        let operationStarted = expectation(description: "Local model operation started")
        let unloadStarted = expectation(description: "Unload started")
        let (releaseStream, releaseContinuation) = AsyncStream<Void>.makeStream()

        let operation = Task {
            try await processor.withLocalModelAccess {
                await recorder.append("operation-start")
                operationStarted.fulfill()
                for await _ in releaseStream { break }
                await recorder.append("operation-end")
            }
        }
        await fulfillment(of: [operationStarted], timeout: 1)

        let unload = Task {
            unloadStarted.fulfill()
            await processor.unloadLLM()
            await recorder.append("unload-end")
        }
        await fulfillment(of: [unloadStarted], timeout: 1)
        try? await Task.sleep(for: .milliseconds(25))
        let eventsWhileOperationIsActive = await recorder.snapshot()
        XCTAssertEqual(eventsWhileOperationIsActive, ["operation-start"])

        releaseContinuation.yield()
        releaseContinuation.finish()
        try? await operation.value
        await unload.value

        let finalEvents = await recorder.snapshot()
        XCTAssertEqual(finalEvents, ["operation-start", "operation-end", "unload-end"])
    }

    func testCancelledLocalModelWaiterDoesNotRunAfterGateOpens() async {
        let processor = TextProcessor()
        let recorder = EventRecorder()
        let holderStarted = expectation(description: "Gate holder started")
        let (releaseStream, releaseContinuation) = AsyncStream<Void>.makeStream()

        let holder = Task {
            try await processor.withLocalModelAccess {
                holderStarted.fulfill()
                for await _ in releaseStream { break }
            }
        }
        await fulfillment(of: [holderStarted], timeout: 1)

        let waiter = Task {
            try await processor.withLocalModelAccess {
                await recorder.append("waiter-ran")
            }
        }
        for _ in 0..<1_000 {
            if await processor.localModelAccessGate.waitingTaskCount == 1 { break }
            await Task.yield()
        }
        let queuedWaiters = await processor.localModelAccessGate.waitingTaskCount
        XCTAssertEqual(queuedWaiters, 1)
        waiter.cancel()

        do {
            try await waiter.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let remainingWaiters = await processor.localModelAccessGate.waitingTaskCount
        XCTAssertEqual(remainingWaiters, 0)

        releaseContinuation.yield()
        releaseContinuation.finish()
        try? await holder.value
        let events = await recorder.snapshot()
        XCTAssertTrue(events.isEmpty)
    }
}
