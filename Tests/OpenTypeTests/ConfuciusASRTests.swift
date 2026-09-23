import AVFoundation
import Foundation
import XCTest
@testable import OpenType

@MainActor
final class ConfuciusASRTests: XCTestCase {
    func testQwenCompatibleModelsShareOneSpeechEngine() {
        let catalog = ModelCatalog(startupCleanup: { _ in Task { 0 } })
        XCTAssertEqual(catalog.asrModels(for: .qwen3).map(\.id), [
            QwenASRModel.defaultID,
            QwenASRModel.confuciusR2T2ID,
        ])
    }

    func testModelRequiresCompleteMLXFilesAndLicenseNotices() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let id = QwenASRModel.confuciusR2T2ID
        let required = ModelCatalog.asrRequiredFiles(for: id)
        XCTAssertTrue(required.contains("model.safetensors"))
        XCTAssertTrue(required.contains("model.safetensors.index.json"))
        XCTAssertTrue(required.contains("MODEL_LICENSE_zh"))
        XCTAssertTrue(required.contains("NOTICE"))
        for file in required where file != "model.safetensors" {
            try Data([1]).write(to: dir.appendingPathComponent(file))
        }
        XCTAssertFalse(ModelCatalog.asrRepoContainsRequiredFiles(id, at: dir))

        try Data().write(to: dir.appendingPathComponent("model.safetensors"))
        XCTAssertFalse(ModelCatalog.asrRepoContainsRequiredFiles(id, at: dir))
        try Data([1]).write(to: dir.appendingPathComponent("model.safetensors"))
        XCTAssertTrue(ModelCatalog.asrRepoContainsRequiredFiles(id, at: dir))

        try FileManager.default.removeItem(at: dir.appendingPathComponent("NOTICE"))
        XCTAssertFalse(ModelCatalog.asrRepoContainsRequiredFiles(id, at: dir))
    }

    func testTailPaddingAddsHalfSecondOfSilence() async throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/assets/demos/confucius-mid-sentence.wav")
        let baseline = try await QwenAudioPreprocessor.withPreparedAudio(from: source) { url in
            try AVAudioFile(forReading: url).length
        }
        let padded = try await QwenAudioPreprocessor.withPreparedAudio(
            from: source,
            tailPaddingFrames: 8_000
        ) { url in
            try AVAudioFile(forReading: url).length
        }
        XCTAssertEqual(padded - baseline, 8_000)
    }

    func testDownloadedModelTranscribesChineseAndEnglish() async throws {
        guard let modelPath = ProcessInfo.processInfo.environment["OPENTYPE_CONFUCIUS_MODEL_PATH"] else {
            throw XCTSkip("Set OPENTYPE_CONFUCIUS_MODEL_PATH to run the model integration test")
        }
        XCTAssertTrue(ModelCatalog.asrRepoContainsRequiredFiles(
            QwenASRModel.confuciusR2T2ID,
            at: URL(fileURLWithPath: modelPath)
        ))
        let engine = QwenNativeASREngine(modelPath: modelPath, modelID: QwenASRModel.confuciusR2T2ID)
        XCTAssertTrue(engine.isReady)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let english = try await engine.transcribe(
            audioURL: root.appendingPathComponent("docs/assets/demos/en-sample.m4a"),
            language: "en"
        )
        let chinese = try await engine.transcribe(
            audioURL: root.appendingPathComponent("docs/assets/demos/zh-sample.m4a"),
            language: "zh"
        )
        print("CONFUCIUS_EN_TEXT=\(english)")
        print("CONFUCIUS_ZH_TEXT=\(chinese)")
        XCTAssertTrue(english.localizedCaseInsensitiveContains("design doc"), english)
        XCTAssertTrue(chinese.contains("周五"), chinese)

        let tail = try await engine.transcribe(
            audioURL: root.appendingPathComponent("docs/assets/demos/confucius-mid-sentence.wav"),
            language: "en"
        )
        print("CONFUCIUS_TAIL_TEXT=\(tail)")
        XCTAssertTrue(tail.localizedCaseInsensitiveContains("follow"), tail)
        XCTAssertFalse(tail.hasSuffix("|"), tail)
    }
}
