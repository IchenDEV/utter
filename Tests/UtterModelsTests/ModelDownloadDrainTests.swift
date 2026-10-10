import Foundation
import XCTest
import UtterContracts
@testable import UtterModels

@MainActor
final class ModelDownloadDrainTests: XCTestCase {
    func testShutdownRejectsPublicationAndDrainsCurrentAndRetiredWriters() async {
        let tasks = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "fixture")
        let old = WriterBarrier()
        let current = WriterBarrier()
        var published = 0
        let first = Task {
            await tasks.run(key: key) { token in
                await old.hold()
                tasks.publishIfCurrent(key, token: token) { published += 1 }
            }
        }
        await old.waitUntilStarted()
        tasks.cancel(key)
        let second = Task {
            await tasks.run(key: key) { token in
                await current.hold()
                tasks.publishIfCurrent(key, token: token) { published += 1 }
            }
        }
        await current.waitUntilStarted()
        let shutdownStarted = expectation(description: "Shutdown started")
        let shutdownFinished = expectation(description: "Shutdown finished")
        shutdownFinished.isInverted = true
        let shutdown = Task {
            shutdownStarted.fulfill()
            await tasks.close()
            shutdownFinished.fulfill()
        }
        await fulfillment(of: [shutdownStarted], timeout: 1)
        await fulfillment(of: [shutdownFinished], timeout: 0.05)
        XCTAssertTrue(tasks.isClosed)
        await tasks.run(key: key) { _ in XCTFail("Closed owner accepted work") }
        await current.release()
        await second.value
        XCTAssertEqual(published, 0)
        await old.release()
        await first.value
        await shutdown.value
        XCTAssertEqual(published, 0)
        await tasks.close()
    }

    func testCancelledExclusiveWaiterReturnsWithoutInterruptingWriter() async {
        let tasks = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "fixture")
        let writer = WriterBarrier()
        let operation = Task { await tasks.run(key: key) { _ in await writer.hold() } }
        await writer.waitUntilStarted()
        let entered = expectation(description: "Exclusive waiter entered")
        let waiter = Task {
            entered.fulfill()
            await tasks.runExclusive(key: key) { _ in XCTFail("Cancelled waiter began deletion") }
        }
        await fulfillment(of: [entered], timeout: 1)
        waiter.cancel()
        await waiter.value
        XCTAssertTrue(tasks.isActive(key))
        await writer.release()
        await operation.value
        await tasks.close()
    }

    func testAlreadyCancelledCallerDoesNotCreateWriter() async {
        let tasks = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "fixture")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await tasks.run(key: key) { _ in XCTFail("Cancelled caller created a writer") }
        }
        await task.value
        XCTAssertFalse(tasks.isActive(key))
        await tasks.close()
    }
}

private actor WriterBarrier {
    private var held: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func hold() async {
        await withCheckedContinuation { continuation in
            held = continuation
            let pending = waiters; waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }
    func waitUntilStarted() async {
        guard held == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { held?.resume(); held = nil }
}
