import Foundation
import XCTest
@testable import OpenType

final class QwenNativeASREngineTests: XCTestCase {
    @MainActor
    func testNativeQwenRemainsTheReleasedLocalASREngine() {
        XCTAssertEqual(
            ModelCatalog.defaultASRModels.map(\.id),
            [QwenASRModel.defaultID]
        )
    }

    func testModelDirectoryRequiresLocalWeightsAndTokenizerInputs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenNativeASREngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for file in ["config.json", "model.safetensors", "tokenizer_config.json", "vocab.json"] {
            try Data([1]).write(to: directory.appendingPathComponent(file))
        }
        XCTAssertFalse(QwenNativeASREngine.modelDirectoryIsReady(directory))

        try Data([1]).write(to: directory.appendingPathComponent("merges.txt"))
        XCTAssertTrue(QwenNativeASREngine.modelDirectoryIsReady(directory))
    }

    func testExistingModelTranscribesRepositorySamplesWithoutDownloadingWeights() async throws {
        guard ProcessInfo.processInfo.environment["OPENTYPE_QWEN_NATIVE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_QWEN_NATIVE_INTEGRATION=1 to run the native Qwen integration test")
        }
        let modelPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["OPENTYPE_QWEN_MODEL_PATH"]
        )
        let modelDirectory = URL(fileURLWithPath: modelPath, isDirectory: true)
        let weightURL = modelDirectory.appendingPathComponent("model.safetensors")
        let weightBefore = try weightURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let safetensorsBefore = try safetensorsFiles(in: modelDirectory)
        let engine = QwenNativeASREngine(modelPath: modelPath)
        XCTAssertTrue(engine.isReady)

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let englishStarted = CFAbsoluteTimeGetCurrent()
        let english = try await engine.transcribe(
            audioURL: repositoryRoot.appendingPathComponent("docs/assets/demos/en-sample.m4a"),
            language: "en"
        )
        let englishElapsed = CFAbsoluteTimeGetCurrent() - englishStarted
        let chineseStarted = CFAbsoluteTimeGetCurrent()
        let chinese = try await engine.transcribe(
            audioURL: repositoryRoot.appendingPathComponent("docs/assets/demos/zh-sample.m4a"),
            language: "zh"
        )
        let chineseElapsed = CFAbsoluteTimeGetCurrent() - chineseStarted

        print("QWEN_NATIVE_EN_SECONDS=\(String(format: "%.3f", englishElapsed))")
        print("QWEN_NATIVE_EN_TEXT=\(english)")
        print("QWEN_NATIVE_ZH_SECONDS=\(String(format: "%.3f", chineseElapsed))")
        print("QWEN_NATIVE_ZH_TEXT=\(chinese)")

        XCTAssertTrue(english.localizedCaseInsensitiveContains("design doc"), english)
        XCTAssertTrue(chinese.contains("周五"), chinese)
        XCTAssertEqual(try safetensorsFiles(in: modelDirectory), safetensorsBefore)
        let weightAfter = try weightURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        XCTAssertEqual(weightAfter.fileSize, weightBefore.fileSize)
        XCTAssertEqual(weightAfter.contentModificationDate, weightBefore.contentModificationDate)
    }

    func testExistingModelNativeBenchmark() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENTYPE_QWEN_NATIVE_BENCHMARK"] == "1" else {
            throw XCTSkip("Set OPENTYPE_QWEN_NATIVE_BENCHMARK=1 to run the native benchmark")
        }
        let modelPath = try XCTUnwrap(environment["OPENTYPE_QWEN_MODEL_PATH"])
        let engine = QwenNativeASREngine(modelPath: modelPath)
        XCTAssertTrue(engine.isReady)

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let samples = [
            (name: "en", file: "en-sample.m4a", language: "en"),
            (name: "zh", file: "zh-sample.m4a", language: "zh"),
            (name: "command", file: "voice-cmd-sample.m4a", language: "zh"),
        ]

        let prepareStarted = CFAbsoluteTimeGetCurrent()
        await engine.prepare()
        print("QWEN_BENCH_ENGINE=native")
        print("QWEN_BENCH_PREPARE_SECONDS=\(formatSeconds(since: prepareStarted))")

        for round in 1...5 {
            for sample in samples {
                let started = CFAbsoluteTimeGetCurrent()
                let text = try await engine.transcribe(
                    audioURL: repositoryRoot.appendingPathComponent("docs/assets/demos/\(sample.file)"),
                    language: sample.language
                )
                print("QWEN_BENCH_\(sample.name.uppercased())_ROUND_\(round)_SECONDS=\(formatSeconds(since: started))")
                print("QWEN_BENCH_\(sample.name.uppercased())_ROUND_\(round)_TEXT=\(text)")
                XCTAssertFalse(text.isEmpty)
            }
        }
    }

    private func safetensorsFiles(in directory: URL) throws -> Set<String> {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return Set(files.filter { $0.pathExtension == "safetensors" }.map(\.lastPathComponent))
    }

    private func formatSeconds(since started: CFAbsoluteTime) -> String {
        String(format: "%.3f", CFAbsoluteTimeGetCurrent() - started)
    }
}
