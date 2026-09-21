import Foundation
import XCTest
@testable import OpenType

final class ModelDownloadRecoveryTests: XCTestCase {
    func testHubCacheRepoNameMatchesPythonLayout() {
        XCTAssertEqual(
            ModelDownloadRecovery.hubCacheRepoName("mlx-community/Qwen3-ASR-1.7B-bf16"),
            "models--mlx-community--Qwen3-ASR-1.7B-bf16"
        )
    }

    func testFindsIncompleteFilesInsideHiddenCacheDirectories() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let downloadCache = root.appendingPathComponent(".cache/huggingface/download")
        try FileManager.default.createDirectory(at: downloadCache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16).write(
            to: downloadCache.appendingPathComponent("AudioEncoder.mlmodelc.abc.incomplete")
        )
        try Data("final".utf8).write(to: root.appendingPathComponent("config.json"))

        let found = ModelDownloadRecovery.incompleteFiles(under: root)
        XCTAssertEqual(found.count, 1)

        let result = ModelDownloadRecovery.purge(found)
        XCTAssertEqual(result.removedFiles, 1)
        XCTAssertEqual(result.removedBytes, 16)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("config.json").path))
        XCTAssertTrue(ModelDownloadRecovery.incompleteFiles(under: root).isEmpty)
    }

    func testWhisperArtifactsPreserveFinalFilesAndOtherRepositories() throws {
        let storage = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storage) }

        let whisperRepo = storage.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        let downloadCache = whisperRepo.appendingPathComponent(".cache/huggingface/download")
        let variant = whisperRepo.appendingPathComponent("openai_whisper-base")
        let variantPartial = downloadCache.appendingPathComponent("openai_whisper-base/TextDecoder.mlmodelc.etag.incomplete")
        try FileManager.default.createDirectory(
            at: variantPartial.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: variant, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 32).write(to: variantPartial)
        try Data("x".utf8).write(to: variant.appendingPathComponent("config.json"))

        let unrelated = storage.appendingPathComponent("models/other/thing")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try Data("y".utf8).write(to: unrelated.appendingPathComponent("keep.incomplete"))

        let urls = ModelDownloadRecovery.incompleteArtifactURLs(
            kind: .whisper,
            modelID: "openai_whisper-base",
            storageRoot: storage,
            cacheRoots: []
        )
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(ModelDownloadRecovery.purge(urls).removedFiles, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: variant.appendingPathComponent("config.json").path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: unrelated.appendingPathComponent("keep.incomplete").path)
        )
    }

    func testLLMArtifactsCoverMaterializedRepoAndSharedCache() throws {
        let storage = makeTemporaryDirectory()
        let cacheRoot = makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: storage)
            try? FileManager.default.removeItem(at: cacheRoot)
        }

        let materialized = storage.appendingPathComponent("models/mlx-community/Qwen3-8B")
        let hubCacheBlobs = cacheRoot.appendingPathComponent("models--mlx-community--Qwen3-8B/blobs")
        try FileManager.default.createDirectory(at: materialized, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hubCacheBlobs, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8).write(
            to: materialized.appendingPathComponent("model.safetensors.etag.incomplete")
        )
        try Data(repeating: 2, count: 4).write(to: hubCacheBlobs.appendingPathComponent("etag2.incomplete"))

        let urls = ModelDownloadRecovery.incompleteArtifactURLs(
            kind: .llm,
            modelID: "mlx-community/Qwen3-8B",
            storageRoot: storage,
            cacheRoots: [cacheRoot]
        )
        XCTAssertEqual(urls.count, 2)

        let result = ModelDownloadRecovery.purge(urls)
        XCTAssertEqual(result.removedFiles, 2)
        XCTAssertEqual(result.removedBytes, 12)
    }

    func testWhisperArtifactsAreScopedToTheRequestedVariant() throws {
        let storage = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storage) }

        let downloadCache = storage
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/.cache/huggingface/download")
        let target = downloadCache.appendingPathComponent(
            "openai_whisper-large-v3-turbo/TextDecoder.mlmodelc.etag.incomplete"
        )
        let otherVariant = downloadCache.appendingPathComponent(
            "openai_whisper-base/AudioEncoder.mlmodelc.etag.incomplete"
        )
        for url in [target, otherVariant] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("partial".utf8).write(to: url)
        }

        let urls = ModelDownloadRecovery.incompleteArtifactURLs(
            kind: .whisper,
            modelID: "openai_whisper-large-v3-turbo",
            storageRoot: storage,
            cacheRoots: []
        )
        XCTAssertEqual(
            urls.map { $0.resolvingSymlinksInPath().path },
            [target.resolvingSymlinksInPath().path]
        )
        XCTAssertEqual(ModelDownloadRecovery.purge(urls).removedFiles, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherVariant.path))
    }

    func testPurgeIgnoresAlreadyRemovedFiles() {
        let missing = makeTemporaryDirectory().appendingPathComponent("gone.incomplete")
        let result = ModelDownloadRecovery.purge([missing])
        XCTAssertTrue(result.isEmpty)
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeRecovery-\(UUID().uuidString)", isDirectory: true)
    }
}

@MainActor
final class DownloadStallWatchdogTests: XCTestCase {
    func testFiresWhenNoProgressArrives() async {
        let watchdog = DownloadStallWatchdog(timeout: 0.05, pollInterval: 0.01)
        let stalled = expectation(description: "watchdog fired")
        watchdog.start { stalled.fulfill() }
        await fulfillment(of: [stalled], timeout: 2)
        watchdog.stop()
    }

    func testProgressSignalOnlyAdvancesOnNewBytesOrFraction() {
        let signal = DownloadProgressSignal()
        XCTAssertTrue(signal.advanced(completedBytes: 10, fraction: 0.1))
        XCTAssertFalse(signal.advanced(completedBytes: 10, fraction: 0.1))
        XCTAssertFalse(signal.advanced(completedBytes: 10, fraction: 0.05))
        XCTAssertTrue(signal.advanced(completedBytes: 11, fraction: 0.1))
        XCTAssertTrue(signal.advanced(completedBytes: 11, fraction: 0.2))
        XCTAssertFalse(signal.advanced(completedBytes: 11, fraction: 0.2))
    }

    func testProgressKeepsDownloadAlive() async {
        let watchdog = DownloadStallWatchdog(timeout: 0.15, pollInterval: 0.01)
        var fired = false
        watchdog.start { fired = true }

        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            watchdog.noteProgress()
        }

        XCTAssertFalse(fired)
        watchdog.stop()
    }
}
