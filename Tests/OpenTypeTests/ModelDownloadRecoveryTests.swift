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

    func testWhisperFlatCacheNamesUseExactVariantBoundaries() throws {
        let storage = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storage) }

        let downloadCache = storage
            .appendingPathComponent(ModelDownloadRecovery.whisperRepositoryRelativePath)
            .appendingPathComponent(".cache/huggingface/download")
        try FileManager.default.createDirectory(at: downloadCache, withIntermediateDirectories: true)

        let target = downloadCache.appendingPathComponent(
            "openai_whisper-large-v3_AudioEncoder.mlmodelc.incomplete"
        )
        let prefixSibling = downloadCache.appendingPathComponent(
            "openai_whisper-large-v3-turbo_AudioEncoder.mlmodelc.incomplete"
        )
        try Data("target".utf8).write(to: target)
        try Data("sibling".utf8).write(to: prefixSibling)

        let urls = ModelDownloadRecovery.incompleteArtifactURLs(
            kind: .whisper,
            modelID: "openai_whisper-large-v3",
            storageRoot: storage,
            cacheRoots: []
        )
        XCTAssertEqual(urls, [target])
    }

    func testRelocationIsolatesOnlyTheRequestedWhisperGeneration() throws {
        let storage = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storage) }

        let repository = storage.appendingPathComponent(
            ModelDownloadRecovery.whisperRepositoryRelativePath
        )
        let target = repository.appendingPathComponent("openai_whisper-large-v3")
        let sibling = repository.appendingPathComponent("openai_whisper-large-v3-turbo")
        let downloadRoot = repository.appendingPathComponent(".cache/huggingface/download")
        let targetPartial = downloadRoot
            .appendingPathComponent("openai_whisper-large-v3/AudioEncoder.mlmodelc.etag.incomplete")
        let siblingPartial = downloadRoot
            .appendingPathComponent("openai_whisper-large-v3-turbo/AudioEncoder.mlmodelc.etag.incomplete")

        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: targetPartial.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: siblingPartial.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("old-target".utf8).write(to: target.appendingPathComponent("config.json"))
        try Data("target-partial".utf8).write(to: targetPartial)
        try Data("sibling-partial".utf8).write(to: siblingPartial)

        let roots = ModelDownloadRecovery.liveArtifactRoots(
            kind: .whisper,
            modelID: "openai_whisper-large-v3",
            storageRoot: storage,
            cacheRoots: []
        )
        let quarantine = storage.appendingPathComponent(".utter-quarantine")
        let relocation = ModelDownloadRecovery.relocate(roots, into: quarantine)

        XCTAssertEqual(relocation.movedDirectories, 2)
        XCTAssertNotNil(relocation.quarantineURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetPartial.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: siblingPartial.path))

        // The replacement owns fresh live paths while the abandoned writer's
        // bytes remain readable in its private generation.
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("new-target".utf8).write(to: target.appendingPathComponent("replacement.json"))
        XCTAssertEqual(
            try Data(contentsOf: target.appendingPathComponent("replacement.json")),
            Data("new-target".utf8)
        )
        let quarantinedPartial = try XCTUnwrap(
            ModelDownloadRecovery.incompleteFiles(under: relocation.quarantineURL!).first
        )
        try Data("old-writer".utf8).write(to: quarantinedPartial)
        let replacementPartial = target.appendingPathComponent("replacement.incomplete")
        try Data("new-writer".utf8).write(to: replacementPartial)
        XCTAssertEqual(try Data(contentsOf: quarantinedPartial), Data("old-writer".utf8))
        XCTAssertEqual(try Data(contentsOf: replacementPartial), Data("new-writer".utf8))

        ModelDownloadRecovery.clearQuarantine(relocation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: relocation.quarantineURL!.path))
        XCTAssertEqual(
            try Data(contentsOf: target.appendingPathComponent("config.json")),
            Data("old-target".utf8)
        )
    }

    func testRelocationKeepsGenerationsSeparateAndCleanupScoped() throws {
        let storage = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storage) }

        let target = storage.appendingPathComponent("models/org/model")
        let quarantine = storage.appendingPathComponent(".utter-quarantine")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: target.appendingPathComponent("partial.incomplete"))

        let first = ModelDownloadRecovery.relocate([target], into: quarantine)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("second".utf8).write(to: target.appendingPathComponent("partial.incomplete"))
        let second = ModelDownloadRecovery.relocate([target], into: quarantine)

        XCTAssertNotEqual(first.quarantineURL, second.quarantineURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.quarantineURL!.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.quarantineURL!.path))

        ModelDownloadRecovery.clearQuarantine(second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.quarantineURL!.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.quarantineURL!.path))
        ModelDownloadRecovery.clearQuarantine(first)
    }

    func testCleanupRestoresAFlatCacheFileThatWasRenamedAfterRelocation() throws {
        let storage = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storage) }

        let repository = storage.appendingPathComponent(
            ModelDownloadRecovery.whisperRepositoryRelativePath
        )
        let quarantine = storage.appendingPathComponent(".utter-quarantine/generation")
        let incomplete = quarantine.appendingPathComponent(
            "files/.cache/huggingface/download/openai_whisper-base_AudioEncoder.mlmodelc.incomplete"
        )
        try FileManager.default.createDirectory(
            at: incomplete.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("finished".utf8).write(to: incomplete)

        let final = incomplete.deletingPathExtension()
        try FileManager.default.moveItem(at: incomplete, to: final)
        let original = repository.appendingPathComponent(
            ".cache/huggingface/download/openai_whisper-base_AudioEncoder.mlmodelc.incomplete"
        )
        let relocation = ModelDownloadRecovery.RelocationResult(
            movedFiles: [
                ModelDownloadRecovery.RelocatedFile(
                    original: original,
                    quarantined: incomplete,
                    originalRoot: repository
                )
            ],
            quarantineURL: quarantine
        )

        ModelDownloadRecovery.clearQuarantine(relocation)

        let restored = repository.appendingPathComponent(
            ".cache/huggingface/download/openai_whisper-base_AudioEncoder.mlmodelc"
        )
        XCTAssertEqual(try Data(contentsOf: restored), Data("finished".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantine.path))
    }

    func testPurgeIgnoresAlreadyRemovedFiles() {
        let missing = makeTemporaryDirectory().appendingPathComponent("gone.incomplete")
        let result = ModelDownloadRecovery.purge([missing])
        XCTAssertTrue(result.isEmpty)
    }

    private func makeTemporaryDirectory() -> URL {
        var buf = [CChar](repeating: 0, count: 1024)
        let resolved = realpath(FileManager.default.temporaryDirectory.path, &buf)
            .map { String(cString: $0) } ?? FileManager.default.temporaryDirectory.path
        return URL(fileURLWithPath: resolved, isDirectory: true)
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
