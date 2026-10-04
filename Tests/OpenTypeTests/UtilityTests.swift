import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterIngress
@testable import UtterModels
import UtterRemoteInference
import UtterContracts
import Foundation
import XCTest
@testable import UtterPresentation

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


    func testModelStorageUsesHubRepoPathForASR() {
        let suffix = ModelStorage.hubModelRepoDir(QwenASRModel.defaultID).path
        XCTAssertTrue(suffix.hasSuffix("/models/mlx-community/Qwen3-ASR-1.7B-bf16"))
        XCTAssertEqual(
            ConfiguredModelFiles.repositoryDirectory(QwenASRModel.defaultID, storageRoot: ModelStorage.huggingFaceBase).path,
            ModelStorage.hubModelRepoDir(QwenASRModel.defaultID).path
        )
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
