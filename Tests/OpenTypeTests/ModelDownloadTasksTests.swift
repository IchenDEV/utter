import XCTest
@testable import OpenType

@MainActor
final class ModelDownloadTasksTests: XCTestCase {
    func testDuplicateRequestsShareOneDownloadTask() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        var starts = 0

        let first = Task { @MainActor in
            await downloads.run(key: key) {
                starts += 1
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        await Task.yield()
        let second = Task { @MainActor in
            await downloads.run(key: key) {
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
            await downloads.run(key: key) {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    observedCancellation = true
                } catch {
                    XCTFail("Unexpected cancellation error: \(error)")
                }
            }
        }
        await Task.yield()
        downloads.cancel(key)
        await task.value

        XCTAssertTrue(observedCancellation)
    }
}
