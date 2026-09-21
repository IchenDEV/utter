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
        // The writer is retained internally while it drains, but no longer
        // owns the current generation slot.
        XCTAssertFalse(downloads.isActive(key))
        XCTAssertFalse(downloads.isCurrent(key, token: token))
        await task.value
        XCTAssertFalse(downloads.isActive(key))
    }

    // MARK: - Retry serialization

    /// A replacement gets its own staging root immediately. The cancelled
    /// dependency writer may remain suspended without blocking Resume.
    func testRetryAfterCancelStartsBeforeOriginalWriterReturns() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        var starts = 0
        var oldReturned = false
        var releaseOld: (() -> Void)?

        let first = Task { @MainActor in
            await downloads.run(key: key) { _ in
                starts += 1
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseOld = {
                        continuation.resume()
                        oldReturned = true
                    }
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
        for _ in 0..<200 where starts < 2 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(starts, 2)
        XCTAssertFalse(oldReturned)
        releaseOld?()
        await first.value
        await retry.value
        XCTAssertTrue(oldReturned)
    }

    /// Application-level counterexample: cancel through ModelCatalog while
    /// its registered writer is still suspended, then start the replacement
    /// through the same catalog-owned task registry before the old writer
    /// returns. This deliberately does not await the first request as the
    /// live download test does.
    func testApplicationCancelAllowsResumeBeforeOldWriterReturns() async {
        let catalog = ModelCatalog.shared
        let key = ModelDownloadKey(kind: .llm, modelID: "test/application-old-writer")
        var oldStarted = false
        var oldReturned = false
        var replacementStarted = false
        var releaseOld: (() -> Void)?

        let old = Task { @MainActor in
            await catalog.downloadTasks.run(key: key) { _ in
                oldStarted = true
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseOld = {
                        continuation.resume()
                        oldReturned = true
                    }
                }
            }
        }
        for _ in 0..<200 where !oldStarted {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(oldStarted, "application writer did not start")

        catalog.cancelDownload(key.modelID, kind: key.kind)
        XCTAssertFalse(catalog.downloadTasks.isActive(key))

        let replacement = Task { @MainActor in
            await catalog.downloadTasks.run(key: key) { _ in
                replacementStarted = true
            }
        }
        for _ in 0..<200 where !replacementStarted {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(replacementStarted, "Resume must start before old writer returns")
        XCTAssertFalse(oldReturned, "old application writer must still be suspended")

        releaseOld?()
        await old.value
        await replacement.value
    }

    /// A duplicate that joined before Cancel is not a user Resume. It must
    /// complete with the cancelled generation and must not claim the restart
    /// replacement after the old writer drains.
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

    /// The old writer keeps its generation root until it returns. The new
    /// generation can publish meanwhile, and a late old continuation cannot
    /// pass the token gate or replace the new model.
    func testCancelledGenerationCannotPublishAfterReplacement() async throws {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "org/model")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeGenerationRace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var oldStage: ModelDownloadStaging?
        var newStage: ModelDownloadStaging?
        var oldPublished = false
        var newPublished = false
        var releaseOld: (() -> Void)?
        var releaseNew: (() -> Void)?

        let old = Task { @MainActor in
            await downloads.run(key: key) { token in
                let staging = ModelStorage.generationStaging(for: token, storageRoot: root)
                oldStage = staging
                defer { ModelStorage.removeGenerationStaging(staging) }
                try? ModelStorage.prepareGeneration(staging)
                let stagedRepo = ModelStorage.hubModelRepoDir(
                    "org/model",
                    downloadBase: staging.downloadBase
                )
                try? FileManager.default.createDirectory(at: stagedRepo, withIntermediateDirectories: true)
                try? Data("old".utf8).write(
                    to: stagedRepo.appendingPathComponent("weights.safetensors")
                )
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseOld = { continuation.resume() }
                }
                oldPublished = ((try? downloads.publishIfCurrent(key, token: token) {
                    try ModelStorage.commitGeneration(
                        kind: .llm,
                        modelID: "org/model",
                        staging: staging
                    )
                }) ?? false)
            }
        }
        for _ in 0..<200 where releaseOld == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(releaseOld, "old writer did not reach its continuation")

        downloads.cancel(key)

        let retry = Task { @MainActor in
            await downloads.run(key: key) { token in
                let staging = ModelStorage.generationStaging(for: token, storageRoot: root)
                newStage = staging
                defer { ModelStorage.removeGenerationStaging(staging) }
                try? ModelStorage.prepareGeneration(staging)
                let stagedRepo = ModelStorage.hubModelRepoDir(
                    "org/model",
                    downloadBase: staging.downloadBase
                )
                try? FileManager.default.createDirectory(at: stagedRepo, withIntermediateDirectories: true)
                try? Data("new".utf8).write(
                    to: stagedRepo.appendingPathComponent("weights.safetensors")
                )
                newPublished = ((try? downloads.publishIfCurrent(key, token: token) {
                    try ModelStorage.commitGeneration(
                        kind: .llm,
                        modelID: "org/model",
                        staging: staging
                    )
                }) ?? false)
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseNew = { continuation.resume() }
                }
            }
        }
        for _ in 0..<200 where !newPublished {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(newPublished)
        XCTAssertNotNil(oldStage)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: oldStage!.root.path),
            "an invalid writer retains its staging root until it returns"
        )
        releaseOld?()
        await old.value
        XCTAssertFalse(oldPublished, "the late old generation must fail the token gate")

        let published = ModelStorage.hubModelRepoDir("org/model", downloadBase: root)
        XCTAssertEqual(
            try Data(contentsOf: published.appendingPathComponent("weights.safetensors")),
            Data("new".utf8)
        )
        releaseNew?()
        await retry.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: newStage!.root.path))
    }

    /// Counterexample the reviewer asked for: two retries racing a cancelled
    /// writer must start exactly one isolated replacement even while the old
    /// writer remains suspended.
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

        for _ in 0..<200 where starts == 0 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(starts, 1, "exactly one replacement must claim the key")
        XCTAssertEqual(maxConcurrentWriters, 2, "old and new generations use separate roots")
        releaseStuck?()
        await retryA.value
        await retryB.value

        XCTAssertEqual(starts, 1)
        XCTAssertEqual(maxConcurrentWriters, 2)
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

    /// Delete may run while a cancelled staged writer drains; the retired
    /// writer has no live-path ownership left to race with deletion.
    func testDeleteRunsWhileCancelledStagedWriterDrains() async {
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

        XCTAssertLessThanOrEqual(maxConcurrentWriters, 2)
    }

    /// A cancelled writer cannot publish while Delete owns the replacement
    /// token, even if the old operation returns late.
    func testDeleteArbitratesAgainstLateCancelledWriter() async {
        let downloads = ModelDownloadTasks()
        let key = ModelDownloadKey(kind: .llm, modelID: "test/model")
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeDeleteRace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try? Data("before".utf8).write(to: file)
        var oldPublished = false
        var releaseStuck: (() -> Void)?
        var releaseDelete: (() -> Void)?
        var deleteRan = false

        let stuck = Task { @MainActor in
            await downloads.run(key: key) { token in
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseStuck = { continuation.resume() }
                }
                oldPublished = ((try? downloads.publishIfCurrent(key, token: token) {
                    try Data("old-late".utf8).write(to: file)
                }) ?? false)
            }
        }
        for _ in 0..<200 where releaseStuck == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNotNil(releaseStuck, "stuck writer did not reach its continuation")
        downloads.cancel(key)

        let deleteTask = Task { @MainActor in
            await downloads.runExclusive(key: key) { _ in
                deleteRan = true
                try? FileManager.default.removeItem(at: file)
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Void, Never>) in
                    releaseDelete = { continuation.resume() }
                }
            }
        }

        for _ in 0..<200 where !deleteRan {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(deleteRan)
        releaseStuck?()
        await stuck.value
        XCTAssertFalse(oldPublished)
        releaseDelete?()
        await deleteTask.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
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
}
