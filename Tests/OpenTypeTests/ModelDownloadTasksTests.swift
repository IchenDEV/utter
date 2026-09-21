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
        // Cancel keeps the slot until the dependency operation returns, but
        // stops the cancelled generation from publishing UI state.
        XCTAssertTrue(downloads.isActive(key))

        XCTAssertFalse(downloads.isCurrent(key, token: token))
        await task.value
        XCTAssertFalse(downloads.isActive(key))
    }

    // MARK: - Retry serialization

    /// Cancellation alone keeps the current generation as the owner. A retry
    /// waits for that operation to return, then starts exactly one replacement.
    func testRetryAfterCancelWaitsForTheOriginalWriter() async {
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
        await first.value
        await retry.value

        XCTAssertEqual(starts, 2)
        XCTAssertTrue(observedCancellation)
    }

    /// A duplicate that joined before Cancel is not a user Resume. It must
    /// complete with the cancelled generation and must not claim the restart
    /// marker after the old writer drains.
    func testDuplicateJoinedBeforeCancelDoesNotRestart() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        var starts = 0
        var releaseOld: (() -> Void)?

        let first = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseOld = { continuation.resume() }
                }
            }
        }
        for _ in 0..<200 where releaseOld == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(releaseOld, "original writer did not reach its continuation")

        let duplicate = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
            }
        }
        await Task.yield()
        XCTAssertEqual(starts, 1, "the duplicate must join the original writer")

        downloads.cancel(key)
        releaseOld?()
        await first.value
        await duplicate.value

        XCTAssertEqual(starts, 1, "a pre-cancel duplicate must not restart after drain")
    }

    /// Regression for the pinned Hub clients: they retain an absolute live URL
    /// over an async network wait. The replacement must not start until the old
    /// operation returns, because a late continuation may write that same URL.
    func testCancelledWriterUsingOriginalPathMustDrainBeforeRetry() async throws {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .asr, modelID: "test/model")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeOriginalPath-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let liveFile = root.appendingPathComponent("models/test/model/blob.incomplete")
        try FileManager.default.createDirectory(
            at: liveFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("before-cancel".utf8).write(to: liveFile)

        var retryStarted = false
        var oldReturned = false
        var releaseOld: (() -> Void)?

        let old = Task { @MainActor in
            await downloads.run(key: key) { _ in
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    // This is intentionally the original URL, not a moved
                    // staging URL. It mirrors the dependency's saved
                    // `incompleteBlobPath`/`incompleteDestination` behavior.
                    releaseOld = {
                        try? Data("old-late-write".utf8).write(to: liveFile)
                        continuation.resume()
                    }
                }
                oldReturned = true
            }
        }
        for _ in 0..<200 where releaseOld == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(releaseOld, "old writer did not reach its continuation")

        downloads.cancel(key)

        let retry = Task { @MainActor in
            await downloads.run(key: key) { _ in
                retryStarted = true
                try? Data("replacement".utf8).write(to: liveFile)
            }
        }
        await Task.yield()

        XCTAssertFalse(retryStarted, "retry must wait for the original-path writer")
        XCTAssertFalse(oldReturned)
        releaseOld?()
        await old.value
        await retry.value

        XCTAssertTrue(retryStarted)
        XCTAssertTrue(oldReturned)
        XCTAssertEqual(try Data(contentsOf: liveFile), Data("replacement".utf8))
    }

    /// Counterexample the reviewer asked for: two retries racing a cancelled
    /// writer must start the replacement exactly once, after the old writer
    /// has drained.
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

        await Task.yield()
        XCTAssertEqual(starts, 0, "retries must wait for the original writer")
        XCTAssertEqual(maxConcurrentWriters, 1)
        releaseStuck?()
        await retryA.value
        await retryB.value

        XCTAssertEqual(starts, 1, "exactly one retry may start its operation")
        XCTAssertEqual(maxConcurrentWriters, 1, "the replacement must wait for the old writer")
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

    /// Delete waits for a cancelled writer that still owns its original live
    /// path, so it cannot remove that path during late dependency I/O.
    func testDeleteWaitsForCancelledWriter() async {
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

    /// File-level counterexample for cancel -> retry -> delete: the old
    /// dependency writer keeps its original live URL, so retry and delete must
    /// both wait for it instead of relying on a directory move.
    func testDeleteWaitsForCancelledOriginalPathWriter() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeDownloadGeneration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let live = root.appendingPathComponent("models/org/model")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        let oldPartial = live.appendingPathComponent("weights.incomplete")
        try Data("old-partial".utf8).write(to: oldPartial)
        let latePayload = root.appendingPathComponent("old-late-payload")

        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "org/model")
        var releaseOld: (() -> Void)?

        let old = Task { @MainActor in
            await downloads.run(key: key) { _ in
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseOld = {
                        // This intentionally writes the original live path,
                        // matching a dependency continuation that retained
                        // its absolute `.incomplete` URL before cancellation.
                        try? Data("old-writer".utf8).write(to: latePayload)
                        try? FileManager.default.createDirectory(
                            at: oldPartial.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try? FileManager.default.removeItem(at: oldPartial)
                        try? FileManager.default.moveItem(at: latePayload, to: oldPartial)
                        continuation.resume()
                    }
                }
            }
        }
        for _ in 0..<200 where releaseOld == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(releaseOld, "old writer did not reach its continuation")

        downloads.cancel(key)

        // Reproduce the rejected quarantine-only design: the old writer still
        // owns the URL it captured before this directory move, while Resume
        // reconstructs the original live path. The coordinator must keep
        // both operations serialized despite the move.
        let relocation = ModelDownloadRecovery.relocate(
            [live],
            into: root.appendingPathComponent("quarantine", isDirectory: true)
        )
        XCTAssertNotNil(relocation.quarantineURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.path))

        let retry = Task { @MainActor in
            await downloads.run(key: key) { _ in
                try? Data("new-writer".utf8).write(to: live.appendingPathComponent("weights.incomplete"))
            }
        }
        await Task.yield()
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.appendingPathComponent("weights.incomplete").path))

        var deleteRan = false
        let delete = Task { @MainActor in
            await downloads.runExclusive(key: key) { _ in
                deleteRan = true
                try? FileManager.default.removeItem(at: live)
            }
        }
        await Task.yield()
        XCTAssertFalse(deleteRan, "delete must wait for the original-path writer")
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.path))

        // The replacement is still waiting for the old writer. Releasing the
        // old writer first proves that the same live URL is never shared.
        releaseOld?()
        await old.value
        await retry.value

        await delete.value

        XCTAssertTrue(deleteRan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPartial.path))
    }
}
