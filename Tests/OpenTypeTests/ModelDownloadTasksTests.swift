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

    func testCancelLetsRetryStartEvenIfTransferIgnoresCancellation() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        var starts = 0

        let stuck = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        for _ in 0..<200 where !downloads.isActive(key) {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(downloads.isActive(key))
        downloads.cancel(key)
        XCTAssertFalse(downloads.isActive(key))

        let retry = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
            }
        }
        await retry.value
        await stuck.value

        XCTAssertEqual(starts, 2)
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
