import Foundation
import XCTest
@testable import OpenType

final class UtilityTests: XCTestCase {
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
        let suffix = ModelStorage.hubModelRepoDir("XiaomiMiMo/MiMo-V2.5-ASR").path
        XCTAssertTrue(suffix.hasSuffix("/models/XiaomiMiMo/MiMo-V2.5-ASR"))
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
            ModelCatalog.estimatedDownloadBytes(from: "MiMo tokenizer ~1,024 MB"),
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
            ModelCatalog.defaultDownloadEstimateBytes(for: LocalASRConfiguration.mimoDefaultModel),
            35_997_080_271
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
