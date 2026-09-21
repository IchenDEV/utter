import Foundation
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

    func testLaterRequestAfterNormalCompletionStartsANewDownload() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        var starts = 0

        await downloads.run(key: key) { _ in
            starts += 1
        }
        await downloads.run(key: key) { _ in
            starts += 1
        }

        XCTAssertEqual(starts, 2, "a later call is a new request after the prior run returned")
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

    func testCancelledRunIsNoLongerCurrent() async {
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
        guard let token = capturedToken else { return XCTFail("no token captured") }
        XCTAssertTrue(downloads.isCurrent(key, token: token))

        downloads.cancel(key)
        // Cancel alone keeps the slot; the owner is still the same token.
        XCTAssertTrue(downloads.isActive(key))

        downloads.abandon(key)
        XCTAssertFalse(downloads.isCurrent(key, token: token))
        XCTAssertFalse(downloads.isActive(key))
        await task.value
    }

    // MARK: - Retry serialization

    /// Cancellation alone keeps the current generation as the owner. A retry
    /// cannot start a second operation until the caller explicitly abandons the
    /// generation after isolating its files.
    func testRetryAfterCancelDoesNotStartASecondWriter() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        var starts = 0
        var observedCancellation = false

        let first = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
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
        XCTAssertTrue(downloads.isActive(key))
        downloads.cancel(key)

        let retry = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
            }
        }
        await retry.value
        await first.value

        XCTAssertEqual(starts, 1)
        XCTAssertTrue(observedCancellation)
    }

    /// A transfer that ignores cancellation is abandoned, not awaited: the retry
    /// starts immediately, so the user is never blocked. Disk safety comes from
    /// the caller having relocated the previous generation first.
    func testAbandonedWriterDoesNotBlockRetry() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .whisper, modelID: "test/model")
        var retryStarted = false
        var stuckReturned = false
        var cleanupCalled = false
        var releaseStuck: (() -> Void)?

        let stuck = Task { @MainActor in
            await downloads.run(key: key) { _ in
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseStuck = { continuation.resume() }
                }
                stuckReturned = true
            }
        }
        for _ in 0..<200 where releaseStuck == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(releaseStuck, "stuck writer did not reach its continuation")

        downloads.cancel(key)
        // The caller has already quarantined the stale cache at this point.
        XCTAssertTrue(downloads.abandon(key) { cleanupCalled = true })

        let retry = Task { @MainActor in
            await downloads.run(key: key) { _ in
                retryStarted = true
            }
        }
        await retry.value

        XCTAssertTrue(retryStarted, "the retry must not wait for the abandoned writer")
        XCTAssertFalse(stuckReturned, "the abandoned writer is still running")
        XCTAssertFalse(cleanupCalled, "old-generation cleanup must wait for old I/O")
        releaseStuck?()
        await stuck.value
        XCTAssertTrue(cleanupCalled)
    }

    /// Counterexample the reviewer asked for: two retries racing a cancelled
    /// writer must start the replacement exactly once.
    func testTwoConcurrentRetriesAfterCancelStartOnlyOneWriter() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        var starts = 0
        var activeWriters = 0
        var maxConcurrentWriters = 0
        var releaseStuck: (() -> Void)?

        let stuck = Task { @MainActor in
            await downloads.run(key: key) { _ in
                activeWriters += 1
                maxConcurrentWriters = max(maxConcurrentWriters, activeWriters)
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseStuck = { continuation.resume() }
                }
                activeWriters -= 1
            }
        }
        for _ in 0..<200 where releaseStuck == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(releaseStuck, "stuck writer did not reach its continuation")
        downloads.cancel(key)
        downloads.abandon(key)

        let retryA = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
                activeWriters += 1
                maxConcurrentWriters = max(maxConcurrentWriters, activeWriters)
                try? await Task.sleep(nanoseconds: 60_000_000)
                activeWriters -= 1
            }
        }
        let retryB = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
                activeWriters += 1
                maxConcurrentWriters = max(maxConcurrentWriters, activeWriters)
                try? await Task.sleep(nanoseconds: 60_000_000)
                activeWriters -= 1
            }
        }

        await retryA.value
        await retryB.value

        XCTAssertEqual(starts, 1, "exactly one retry may start its operation")
        XCTAssertEqual(maxConcurrentWriters, 2, "the old writer and replacement use isolated generations")
        releaseStuck?()
        await stuck.value
    }

    /// Two ordinary (non-cancelled) retries must not both start either.
    func testTwoConcurrentRetriesWithoutCancelStartOnlyOneWriter() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .asr, modelID: "test/model")
        var starts = 0
        var activeWriters = 0
        var maxConcurrentWriters = 0

        let first = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
                activeWriters += 1
                maxConcurrentWriters = max(maxConcurrentWriters, activeWriters)
                try? await Task.sleep(nanoseconds: 80_000_000)
                activeWriters -= 1
            }
        }
        for _ in 0..<200 where activeWriters == 0 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let second = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
            }
        }

        await first.value
        await second.value
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(maxConcurrentWriters, 1)
    }

    // MARK: - Delete serialization

    /// Delete during a still-winding-down cancelled transfer must not run its
    /// file work concurrently with the writer.
    func testDeleteWaitsForCancelledWriterThatHonoursCancellation() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .whisper, modelID: "test/model")
        var activeWriters = 0
        var maxConcurrentWriters = 0

        let writer = Task { @MainActor in
            await downloads.run(key: key) { _ in
                activeWriters += 1
                maxConcurrentWriters = max(maxConcurrentWriters, activeWriters)
                try? await Task.sleep(nanoseconds: 100_000_000)
                activeWriters -= 1
            }
        }
        for _ in 0..<200 where activeWriters == 0 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        downloads.cancel(key)

        let deleteTask = Task { @MainActor in
            await downloads.runExclusive(key: key) { _ in
                activeWriters += 1
                maxConcurrentWriters = max(maxConcurrentWriters, activeWriters)
                try? await Task.sleep(nanoseconds: 30_000_000)
                activeWriters -= 1
            }
        }

        await deleteTask.value
        await writer.value

        XCTAssertEqual(maxConcurrentWriters, 1, "delete must not overlap the cancelled writer")
    }

    /// Delete after an abandon still waits for the abandoned writer, so it never
    /// deletes the quarantine directory out from under an active writer.
    func testDeleteWaitsForAbandonedWriter() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        var activeWriters = 0
        var maxConcurrentWriters = 0
        var releaseStuck: (() -> Void)?

        let stuck = Task { @MainActor in
            await downloads.run(key: key) { _ in
                activeWriters += 1
                maxConcurrentWriters = max(maxConcurrentWriters, activeWriters)
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseStuck = { continuation.resume() }
                }
                activeWriters -= 1
            }
        }
        for _ in 0..<200 where releaseStuck == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(releaseStuck, "stuck writer did not reach its continuation")
        downloads.cancel(key)
        downloads.abandon(key)

        let deleteTask = Task { @MainActor in
            await downloads.runExclusive(key: key) { _ in
                activeWriters += 1
                maxConcurrentWriters = max(maxConcurrentWriters, activeWriters)
                activeWriters -= 1
            }
        }

        await Task.yield()
        releaseStuck?()
        await deleteTask.value
        await stuck.value
        XCTAssertEqual(maxConcurrentWriters, 1)
    }

    func testDeleteRunsWhenNoDownloadIsActive() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .asr, modelID: "test/model")
        var deleteRan = false

        await downloads.runExclusive(key: key) { _ in
            deleteRan = true
        }
        XCTAssertTrue(deleteRan)
        XCTAssertFalse(downloads.isActive(key), "the exclusive slot is released afterwards")
    }

    /// File-level counterexample for cancel -> retry -> delete: the retired
    /// writer keeps writing in quarantine, while delete waits and only removes
    /// the replacement's live path after the retired I/O exits.
    func testDeleteWaitsForRetiredGenerationBeforeRemovingLivePath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeDownloadGeneration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let live = root.appendingPathComponent("models/org/model")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        let oldPartial = live.appendingPathComponent("weights.incomplete")
        try Data("old-partial".utf8).write(to: oldPartial)

        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "org/model")
        var releaseOld: (() -> Void)?
        var quarantinedPartial: URL?

        let old = Task { @MainActor in
            await downloads.run(key: key) { _ in
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseOld = {
                        if let quarantinedPartial {
                            try? Data("old-writer".utf8).write(to: quarantinedPartial)
                        }
                        continuation.resume()
                    }
                }
            }
        }
        for _ in 0..<200 where releaseOld == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(releaseOld, "old writer did not reach its continuation")

        let relocation = ModelDownloadRecovery.relocate([live], into: root.appendingPathComponent("quarantine"))
        quarantinedPartial = try XCTUnwrap(
            ModelDownloadRecovery.incompleteFiles(under: try XCTUnwrap(relocation.quarantineURL)).first
        )
        downloads.cancel(key)
        XCTAssertTrue(downloads.abandon(key) {
            ModelDownloadRecovery.clearQuarantine(relocation)
        })

        let retry = Task { @MainActor in
            await downloads.run(key: key) { _ in
                try? FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
                try? Data("new-writer".utf8).write(to: live.appendingPathComponent("weights.incomplete"))
            }
        }
        await retry.value

        var deleteRan = false
        let delete = Task { @MainActor in
            await downloads.runExclusive(key: key) { _ in
                deleteRan = true
                try? FileManager.default.removeItem(at: live)
            }
        }
        await Task.yield()
        XCTAssertFalse(deleteRan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path))

        releaseOld?()
        await old.value
        await delete.value

        XCTAssertTrue(deleteRan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPartial.path))
    }
}
