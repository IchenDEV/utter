import XCTest
@testable import OpenType

@MainActor
final class ModelDownloadTasksTests: XCTestCase {
    func testDuplicateRequestsShareOneDownloadTask() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        var starts = 0

        let first = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        await Task.yield()
        let second = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
            }
        }

        await first.value
        await second.value
        XCTAssertEqual(starts, 1)
    }

    func testCancelPropagatesToActiveDownloadTask() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .asr, modelID: "test/model")
        var observedCancellation = false

        let task = Task { @MainActor in
            await downloads.run(key: key) { _ in
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    observedCancellation = true
                } catch {
                    XCTFail("Unexpected cancellation error: \(error)")
                }
            }
        }
        for _ in 0..<200 where !downloads.isActive(key) {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        downloads.cancel(key)
        await task.value

        XCTAssertTrue(observedCancellation)
    }

    func testRetryAfterCancelNeverOverlapsTheCancelledWriter() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        var firstToken: UUID?
        var activeWriters = 0
        var maxConcurrentWriters = 0
        var writeOrder: [String] = []

        func beginWrite(_ label: String) {
            activeWriters += 1
            maxConcurrentWriters = max(maxConcurrentWriters, activeWriters)
            writeOrder.append("\(label)-start")
        }
        func endWrite(_ label: String) {
            writeOrder.append("\(label)-end")
            activeWriters -= 1
        }

        let cancelled = Task { @MainActor in
            await downloads.run(key: key) { token in
                firstToken = token
                beginWrite("cancelled")
                try? await Task.sleep(nanoseconds: 120_000_000)
                endWrite("cancelled")
            }
        }
        for _ in 0..<200 where activeWriters == 0 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(activeWriters, 1)

        downloads.cancel(key)
        XCTAssertTrue(downloads.isActive(key), "cancel keeps the single-writer slot")
        if let token = firstToken {
            XCTAssertFalse(downloads.isCurrent(key, token: token))
        }

        let retry = Task { @MainActor in
            await downloads.run(key: key) { _ in
                beginWrite("retry")
                endWrite("retry")
            }
        }
        await retry.value
        await cancelled.value

        XCTAssertEqual(maxConcurrentWriters, 1, "the retry must wait for the cancelled writer to exit")
        XCTAssertEqual(writeOrder, ["cancelled-start", "cancelled-end", "retry-start", "retry-end"])
    }

    func testCancelledRunNoLongerReportsCurrent() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .asr, modelID: "test/model")
        var capturedToken: UUID?

        let task = Task { @MainActor in
            await downloads.run(key: key) { token in
                capturedToken = token
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        for _ in 0..<200 where capturedToken == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let token = try? XCTUnwrap(capturedToken)
        XCTAssertNotNil(token)
        if let token { XCTAssertTrue(downloads.isCurrent(key, token: token)) }

        downloads.cancel(key)
        if let token { XCTAssertFalse(downloads.isCurrent(key, token: token)) }
        await task.value
    }
}
