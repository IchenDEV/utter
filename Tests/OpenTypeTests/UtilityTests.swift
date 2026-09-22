import Foundation
import XCTest
@testable import OpenType

private final class StartupCleanupGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSignal = DispatchSemaphore(value: 0)
    private var entered = false
    private var exited = false
    private var released = false

    func enterAndWait() {
        lock.lock()
        entered = true
        let wasReleased = released
        lock.unlock()
        if !wasReleased {
            releaseSignal.wait()
        }
    }

    func exit() {
        lock.lock()
        exited = true
        lock.unlock()
    }

    func release() {
        lock.lock()
        guard !released else {
            lock.unlock()
            return
        }
        released = true
        lock.unlock()
        releaseSignal.signal()
    }

    func snapshot() -> (entered: Bool, exited: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (entered, exited)
    }
}

final class UtilityTests: XCTestCase {
    private enum InjectedReplacementFailure: Error {
        case replacement
    }

    func testModelStorageMakesStableLocalIDs() {
        XCTAssertEqual(ModelStorage.makeLocalID(
            prefix: "llm",
            folderName: "Qwen",
            existing: []
        ), "local/llm-Qwen")
        XCTAssertEqual(ModelStorage.makeLocalID(
            prefix: "whisper",
            folderName: "",
            existing: []
        ), "local/whisper-model")
        XCTAssertEqual(ModelStorage.makeLocalID(
            prefix: "llm",
            folderName: "Qwen",
            existing: ["local/llm-Qwen"]
        ), "local/llm-Qwen-2")
        XCTAssertEqual(ModelStorage.makeLocalID(
            prefix: "llm",
            folderName: "Qwen",
            existing: ["local/llm-Qwen", "local/llm-Qwen-2"]
        ), "local/llm-Qwen-3")
    }

    func testModelStorageDirectorySize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeTests-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 12).write(to: root.appendingPathComponent("a.bin"))
        try Data(repeating: 2, count: 8).write(to: nested.appendingPathComponent("b.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(ModelStorage.directorySize(at: root), 20)
        XCTAssertEqual(ModelStorage.directorySize(at: root.appendingPathComponent("missing")), 0)
    }

    func testModelStorageUsesHubRepoPathForASR() {
        let suffix = ModelStorage.hubModelRepoDir(QwenASRModel.defaultID).path
        XCTAssertTrue(suffix.hasSuffix("/models/mlx-community/Qwen3-ASR-1.7B-bf16"))
    }

    func testGenerationStagingSeparatesDownloadAndHubCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeGeneration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let staging = ModelStorage.generationStaging(
            for: UUID(),
            storageRoot: root
        )
        XCTAssertNotEqual(staging.downloadBase, staging.hubCache.cacheDirectory)
        XCTAssertTrue(staging.downloadBase.path.hasPrefix(staging.root.path))
        XCTAssertTrue(staging.hubCache.cacheDirectory.path.hasPrefix(staging.root.path))

        try ModelStorage.prepareGeneration(staging)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.downloadBase.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: staging.hubCache.cacheDirectory.path)
        )
        ModelStorage.removeGenerationStaging(staging)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.root.path))
    }

    func testCommitMaterializesHubSymlinkBeforeStagingCleanup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeCommit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let staging = ModelStorage.generationStaging(
            for: UUID(),
            storageRoot: root
        )
        try ModelStorage.prepareGeneration(staging)
        let stagedRepo = ModelStorage.hubModelRepoDir(
            "org/model",
            downloadBase: staging.downloadBase
        )
        let blob = staging.hubCache.cacheDirectory
            .appendingPathComponent("models--org--model/blobs/weights.bin")
        try FileManager.default.createDirectory(
            at: stagedRepo,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: blob.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: stagedRepo.appendingPathComponent("config.json"))
        try Data("committed-weights".utf8).write(to: blob)
        try FileManager.default.createSymbolicLink(
            at: stagedRepo.appendingPathComponent("weights.safetensors"),
            withDestinationURL: blob
        )

        XCTAssertTrue(ModelStorage.llmRepoIsComplete(at: stagedRepo))
        try ModelStorage.commitGeneration(
            kind: .llm,
            modelID: "org/model",
            staging: staging
        )
        ModelStorage.removeGenerationStaging(staging)

        let published = ModelStorage.hubModelRepoDir("org/model", downloadBase: root)
        XCTAssertEqual(
            try Data(contentsOf: published.appendingPathComponent("weights.safetensors")),
            Data("committed-weights".utf8)
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: published.appendingPathComponent("weights.safetensors").path
        )
        XCTAssertNotEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertTrue(ModelStorage.llmRepoIsComplete(at: published))
    }

    func testFailedCommitKeepsThePreviouslyPublishedModel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeCommitFailure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let previous = ModelStorage.hubModelRepoDir("org/model", downloadBase: root)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data("old-config".utf8).write(to: previous.appendingPathComponent("config.json"))
        try Data("old-weights".utf8).write(
            to: previous.appendingPathComponent("weights.safetensors")
        )

        let staging = ModelStorage.generationStaging(for: UUID(), storageRoot: root)
        try ModelStorage.prepareGeneration(staging)
        let stagedRepo = ModelStorage.hubModelRepoDir(
            "org/model",
            downloadBase: staging.downloadBase
        )
        try FileManager.default.createDirectory(at: stagedRepo, withIntermediateDirectories: true)
        try Data("new-config".utf8).write(to: stagedRepo.appendingPathComponent("config.json"))
        try Data("new-weights".utf8).write(
            to: stagedRepo.appendingPathComponent("weights.safetensors")
        )

        let prepared = try ModelStorage.prepareGenerationCommit(
            kind: .llm,
            modelID: "org/model",
            staging: staging
        )
        defer { ModelStorage.discardPreparedGeneration(prepared) }

        XCTAssertThrowsError(
            try ModelStorage.publishPreparedGeneration(prepared) { candidate, destination in
                // Simulate a replacement that moved the candidate but failed
                // while returning from the filesystem operation. This enters
                // the restore branch instead of failing during preparation.
                try FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: candidate, to: destination)
                throw InjectedReplacementFailure.replacement
            }
        )
        XCTAssertEqual(
            try Data(contentsOf: previous.appendingPathComponent("config.json")),
            Data("old-config".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: previous.appendingPathComponent("weights.safetensors")),
            Data("old-weights".utf8)
        )
    }

    func testStartupCleanupRemovesAllOrphanedGenerationArtifacts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeRestartCleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let stale = ModelStorage.generationStaging(for: UUID(), storageRoot: root)
        let secondStale = ModelStorage.generationStaging(for: UUID(), storageRoot: root)
        try ModelStorage.prepareGeneration(stale)
        try ModelStorage.prepareGeneration(secondStale)
        try Data("partial".utf8).write(
            to: stale.downloadBase.appendingPathComponent("weights.incomplete")
        )
        let published = ModelStorage.hubModelRepoDir("org/model", downloadBase: root)
        try FileManager.default.createDirectory(at: published, withIntermediateDirectories: true)
        try Data("old-config".utf8).write(to: published.appendingPathComponent("config.json"))
        try Data("old-weights".utf8).write(
            to: published.appendingPathComponent("weights.safetensors")
        )

        let stagedRepo = ModelStorage.hubModelRepoDir(
            "org/model",
            downloadBase: stale.downloadBase
        )
        try FileManager.default.createDirectory(at: stagedRepo, withIntermediateDirectories: true)
        try Data("new-config".utf8).write(to: stagedRepo.appendingPathComponent("config.json"))
        try Data("new-weights".utf8).write(
            to: stagedRepo.appendingPathComponent("weights.safetensors")
        )
        let prepared = try ModelStorage.prepareGenerationCommit(
            kind: .llm,
            modelID: "org/model",
            staging: stale
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.candidate.path))
        XCTAssertTrue(
            prepared.backup.map { FileManager.default.fileExists(atPath: $0.path) } == true
        )

        let cleanupRoot = root.appendingPathComponent(
            ModelStorage.cleanupDirectoryName,
            isDirectory: true
        )
        let cleanupArtifact = cleanupRoot.appendingPathComponent("retired", isDirectory: true)
        try FileManager.default.createDirectory(at: cleanupArtifact, withIntermediateDirectories: true)
        try Data("retired".utf8).write(to: cleanupArtifact.appendingPathComponent("weights.bin"))

        let generationRoot = root.appendingPathComponent(
            ModelStorage.generationDirectoryName,
            isDirectory: true
        )
        let childrenBefore = try FileManager.default.contentsOfDirectory(
            at: generationRoot,
            includingPropertiesForKeys: nil,
            options: []
        )
        XCTAssertEqual(childrenBefore.count, 2)

        // The cleanup helper is called by ModelCatalog before a restarted
        // process can create any download writer. It covers generation roots,
        // prepared candidates, rollback backups, and retired cleanup roots.
        let removed = ModelStorage.cleanupOrphanedGenerationStaging(storageRoot: root)
        XCTAssertEqual(removed, 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.root.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondStale.root.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.candidate.path))
        XCTAssertFalse(
            prepared.backup.map { FileManager.default.fileExists(atPath: $0.path) } == true
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanupArtifact.path))
        XCTAssertEqual(
            try Data(contentsOf: published.appendingPathComponent("config.json")),
            Data("old-config".utf8)
        )
    }

    @MainActor
    func testStartupCleanupKeepsMainActorResponsive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeStartupCleanupResponsiveness-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let staging = ModelStorage.generationStaging(for: UUID(), storageRoot: root)
        try ModelStorage.prepareGeneration(staging)
        let debris = staging.downloadBase.appendingPathComponent("orphaned-files", isDirectory: true)
        try FileManager.default.createDirectory(at: debris, withIntermediateDirectories: true)
        // A synchronous startup removeItem on the MainActor must remain busy
        // long enough for this probe to observe the regression. The new
        // background entry point performs the same real recursive deletion
        // away from the actor.
        for index in 0..<2_048 {
            try Data(repeating: UInt8(index % 251), count: 32_768).write(
                to: debris.appendingPathComponent("chunk-\(index).bin")
            )
        }

        var cleanupStarted = false
        var cleanupFinished = false
        let cleanup = Task { @MainActor in
            cleanupStarted = true
            _ = await ModelStorage.cleanupOrphanedGenerationStagingInBackground(
                storageRoot: root
            ).value
            cleanupFinished = true
        }
        while !cleanupStarted {
            await Task.yield()
        }

        var heartbeats = 0
        let heartbeat = Task { @MainActor in
            while !cleanupFinished {
                heartbeats += 1
                await Task.yield()
            }
        }
        await cleanup.value
        await heartbeat.value

        XCTAssertGreaterThan(
            heartbeats,
            0,
            "MainActor should service work while startup cleanup removes orphaned files"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.root.path))
    }

    @MainActor
    func testModelCatalogInitializerStartupCleanupKeepsMainActorResponsive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeCatalogStartupCleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let staging = ModelStorage.generationStaging(for: UUID(), storageRoot: root)
        try ModelStorage.prepareGeneration(staging)
        let debris = staging.downloadBase.appendingPathComponent("orphaned-files", isDirectory: true)
        try FileManager.default.createDirectory(at: debris, withIntermediateDirectories: true)
        for index in 0..<128 {
            try Data(repeating: UInt8(index % 251), count: 8_192).write(
                to: debris.appendingPathComponent("chunk-\(index).bin")
            )
        }

        let gate = StartupCleanupGate()
        var factoryCalls = 0
        let catalog = ModelCatalog(
            startupStorageRoot: root,
            startupCleanup: { storageRoot in
                factoryCalls += 1
                return ModelStorage.cleanupOrphanedGenerationStagingInBackground(
                    storageRoot: storageRoot,
                    onEnter: { gate.enterAndWait() },
                    onExit: { gate.exit() }
                )
            }
        )

        // A detached watchdog releases the gate even if a MainActor child-task
        // mutation blocks the test actor before its heartbeat can run.
        let timeoutRelease = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            gate.release()
        }
        defer {
            gate.release()
            timeoutRelease.cancel()
        }

        let entryDeadline = Date().addingTimeInterval(1)
        while !gate.snapshot().entered && Date() < entryDeadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        var heartbeats = 0
        var heartbeatObservedBeforeExit = false
        let heartbeat = Task { @MainActor in
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                let state = gate.snapshot()
                if state.entered, !state.exited {
                    heartbeats += 1
                    heartbeatObservedBeforeExit = true
                    gate.release()
                    return
                }
                if state.exited { return }
                await Task.yield()
            }
        }

        await catalog.awaitStartupCleanup()
        await heartbeat.value

        let state = gate.snapshot()
        XCTAssertEqual(factoryCalls, 1, "ModelCatalog.init must invoke the injected startup factory")
        XCTAssertTrue(state.entered, "startup cleanup must enter the path-scoped barrier")
        XCTAssertTrue(heartbeatObservedBeforeExit, "MainActor heartbeat must occur after entry and before exit")
        XCTAssertGreaterThan(heartbeats, 0)
        XCTAssertTrue(state.exited, "startup cleanup must release its exit barrier")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.root.path))
    }

    @MainActor
    func testGenerationPreparationKeepsMainActorResponsive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypePreparationResponsiveness-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let staging = ModelStorage.generationStaging(for: UUID(), storageRoot: root)
        try ModelStorage.prepareGeneration(staging)
        let stagedRepo = ModelStorage.hubModelRepoDir(
            "org/model",
            downloadBase: staging.downloadBase
        )
        try FileManager.default.createDirectory(at: stagedRepo, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: stagedRepo.appendingPathComponent("config.json"))
        try Data(repeating: 7, count: 16_000_000).write(
            to: stagedRepo.appendingPathComponent("weights.safetensors")
        )

        var heartbeats = 0
        var preparationFinished = false
        let preparation = Task { @MainActor in
            do {
                let prepared = try await ModelStorage.prepareGenerationCommitOffMainActor(
                    kind: .llm,
                    modelID: "org/model",
                    staging: staging
                )
                preparationFinished = true
                return prepared
            } catch {
                preparationFinished = true
                throw error
            }
        }
        // Let the preparation task reach its detached await before starting
        // the probe. A synchronous MainActor copy would keep this probe from
        // running until preparationFinished became true.
        await Task.yield()
        let heartbeat = Task { @MainActor in
            while !preparationFinished {
                heartbeats += 1
                await Task.yield()
            }
        }
        let prepared = try await preparation.value
        await heartbeat.value
        ModelStorage.discardPreparedGeneration(prepared)

        XCTAssertGreaterThan(heartbeats, 0, "MainActor should service work while preparation copies files")
    }

    @MainActor
    func testGenerationCleanupKeepsMainActorResponsive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeCleanupResponsiveness-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let staging = ModelStorage.generationStaging(for: UUID(), storageRoot: root)
        try ModelStorage.prepareGeneration(staging)
        let stagedRepo = ModelStorage.hubModelRepoDir(
            "org/model",
            downloadBase: staging.downloadBase
        )
        try FileManager.default.createDirectory(at: stagedRepo, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: stagedRepo.appendingPathComponent("config.json"))
        try Data(repeating: 7, count: 32_000_000).write(
            to: stagedRepo.appendingPathComponent("weights.safetensors")
        )
        let prepared = try ModelStorage.prepareGenerationCommit(
            kind: .llm,
            modelID: "org/model",
            staging: staging
        )

        var heartbeats = 0
        var cleanupFinished = false
        let heartbeat = Task { @MainActor in
            while !cleanupFinished {
                heartbeats += 1
                await Task.yield()
            }
        }
        let cleanup = Task { @MainActor in
            await ModelStorage.discardPreparedGenerationOffMainActor(prepared)
            cleanupFinished = true
        }
        await cleanup.value
        await heartbeat.value

        XCTAssertGreaterThan(heartbeats, 0, "MainActor should service work while cleanup removes files")
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.candidate.path))
        XCTAssertFalse(
            prepared.backup.map { FileManager.default.fileExists(atPath: $0.path) } == true
        )
    }

    func testModelStorageRequiresWeightsBeforeLLMIsComplete() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
        XCTAssertFalse(ModelStorage.llmRepoIsComplete(at: root))

        try Data("weights".utf8).write(to: root.appendingPathComponent("model.safetensors"))
        XCTAssertTrue(ModelStorage.llmRepoIsComplete(at: root))
    }

    func testModelStorageRequiresEveryIndexedLLMShard() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
        let index = """
        {"weight_map":{"first":"model-00001-of-00002.safetensors","second":"model-00002-of-00002.safetensors"}}
        """
        try Data(index.utf8).write(to: root.appendingPathComponent("model.safetensors.index.json"))
        try Data("one".utf8).write(to: root.appendingPathComponent("model-00001-of-00002.safetensors"))
        XCTAssertFalse(ModelStorage.llmRepoIsComplete(at: root))

        try Data("two".utf8).write(to: root.appendingPathComponent("model-00002-of-00002.safetensors"))
        XCTAssertTrue(ModelStorage.llmRepoIsComplete(at: root))
    }

    func testModelStorageRequiresAllWhisperComponents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("MelSpectrogram.mlmodelc"),
            withIntermediateDirectories: true
        )
        try Data("model".utf8).write(
            to: root.appendingPathComponent("MelSpectrogram.mlmodelc/model.bin")
        )
        XCTAssertFalse(ModelStorage.whisperModelIsComplete(at: root))

        for name in ["AudioEncoder", "TextDecoder"] {
            let component = root.appendingPathComponent("\(name).mlmodelc")
            try FileManager.default.createDirectory(
                at: component,
                withIntermediateDirectories: true
            )
            try Data("model".utf8).write(to: component.appendingPathComponent("model.bin"))
        }
        XCTAssertTrue(ModelStorage.whisperModelIsComplete(at: root))
    }

    @MainActor
    func testDownloadEstimateParsesModelHints() {
        XCTAssertEqual(
            ModelCatalog.estimatedDownloadBytes(from: "整理质量最佳 5-bit ~5.5 GB"),
            5_500_000_000
        )
        XCTAssertEqual(
            ModelCatalog.estimatedDownloadBytes(from: "Qwen3.5 极速 ~620 MB"),
            620_000_000
        )
        XCTAssertEqual(
            ModelCatalog.estimatedDownloadBytes(from: "ASR tokenizer ~1,024 MB"),
            1_024_000_000
        )
        XCTAssertEqual(
            ModelCatalog.estimatedDownloadBytes(from: "compact model ~750MiB"),
            786_432_000
        )
        XCTAssertEqual(
            ModelCatalog.estimatedDownloadBytes(from: "about 2.5G download"),
            2_500_000_000
        )
        XCTAssertNil(ModelCatalog.estimatedDownloadBytes(from: "本地语音识别模型 + audio tokenizer"))
    }

    @MainActor
    func testDefaultDownloadEstimatesUseRepositoryMetadata() {
        XCTAssertEqual(
            ModelCatalog.defaultDownloadEstimateBytes(for: "mlx-community/Qwen3.5-9B-5bit"),
            7_096_163_574
        )
        XCTAssertEqual(
            ModelCatalog.defaultDownloadEstimateBytes(
                for: "mlx-community/Llama-4-Maverick-17B-128E-Instruct-4bit"
            ),
            225_923_469_800
        )
        XCTAssertEqual(
            ModelCatalog.defaultDownloadEstimateBytes(for: QwenASRModel.defaultID),
            4_080_707_826
        )
    }

    @MainActor
    func testDefaultModelHintsStayCloseToDownloadEstimates() {
        let llmHints = ModelCatalog.defaultLLMModels.map { (id: $0.0, hint: $0.2) }
        let asrHints = ModelCatalog.defaultASRModels.map { (id: $0.id, hint: $0.hint) }

        for entry in llmHints + asrHints {
            guard let exactBytes = ModelCatalog.defaultDownloadEstimateBytes(for: entry.id),
                  let hintBytes = ModelCatalog.estimatedDownloadBytes(from: entry.hint) else {
                XCTFail("Missing displayed download estimate for \(entry.id)")
                continue
            }

            let delta = abs(Double(hintBytes - exactBytes)) / Double(exactBytes)
            XCTAssertLessThanOrEqual(delta, 0.05, "\(entry.id) hint is too far from exact estimate")
        }
    }

    func testDownloadSpeedHidesSubByteNoise() {
        let info = DownloadProgressInfo(
            fraction: 0.81,
            elapsedSeconds: 1701,
            completedBytes: 4_500_000_000,
            totalBytes: 5_500_000_000,
            speedBytesPerSecond: 0.4
        )

        XCTAssertEqual(info.remainingText, "1.0 GB")
        XCTAssertEqual(info.speedText, L("download.unknown"))
    }

    func testDownloadProgressInfoSanitizesInvalidValues() {
        let info = DownloadProgressInfo(
            fraction: .infinity,
            elapsedSeconds: -.infinity,
            completedBytes: -42,
            totalBytes: -1,
            speedBytesPerSecond: .nan
        )

        XCTAssertEqual(info.fraction, 0)
        XCTAssertEqual(info.elapsedSeconds, 0)
        XCTAssertEqual(info.completedBytes, 0)
        XCTAssertEqual(info.totalBytes, 0)
        XCTAssertEqual(info.speedBytesPerSecond, 0)
    }

    func testDownloadProgressTrackerUsesInitialBytesForSpeed() {
        let start = Date(timeIntervalSince1970: 10)
        let tracker = DownloadProgressTracker(startDate: start, initialBytes: 1_000)

        let info = tracker.update(
            completedBytes: 1_500,
            totalBytes: 2_000,
            at: start.addingTimeInterval(1)
        )

        XCTAssertEqual(info.fraction, 0.75)
        XCTAssertEqual(info.speedBytesPerSecond, 500)
    }

    func testDownloadProgressTrackerClearsSpeedWhenBytesReset() {
        let start = Date(timeIntervalSince1970: 10)
        let tracker = DownloadProgressTracker(startDate: start)
        _ = tracker.update(completedBytes: 1_500, totalBytes: 2_000, at: start.addingTimeInterval(1))

        let info = tracker.update(
            completedBytes: 200,
            totalBytes: 2_000,
            fraction: 0.1,
            at: start.addingTimeInterval(2)
        )

        XCTAssertEqual(info.fraction, 0.1)
        XCTAssertEqual(info.speedBytesPerSecond, 0)
        XCTAssertEqual(info.speedText, L("download.unknown"))
    }

    func testGzipRoundTripForTextAndBinaryData() throws {
        let text = Data("OpenType voice input. 你好，世界。".utf8)
        let compressedText = try XCTUnwrap(Gzip.compress(text))
        XCTAssertGreaterThan(compressedText.count, 18)
        XCTAssertEqual(Gzip.decompress(compressedText), text)

        let binary = Data((0..<255).map(UInt8.init))
        let compressedBinary = try XCTUnwrap(Gzip.compress(binary))
        XCTAssertEqual(Gzip.decompress(compressedBinary), binary)
    }

    func testGzipHandlesEmptyAndInvalidInput() throws {
        XCTAssertEqual(Gzip.compress(Data()), Data())
        XCTAssertNil(Gzip.decompress(Data()))
        XCTAssertNil(Gzip.decompress(Data("not gzip".utf8)))

        var truncated = try XCTUnwrap(Gzip.compress(Data("hello".utf8)))
        truncated.removeLast(4)
        XCTAssertNil(Gzip.decompress(truncated))
    }
}
