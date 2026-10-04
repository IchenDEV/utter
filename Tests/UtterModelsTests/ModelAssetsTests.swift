import Foundation
import XCTest
@testable import UtterModels

final class ModelAssetsTests: XCTestCase {
    func testEmptyComponentDirectoriesDoNotCountAsModelData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("\(component).mlmodelc/empty"),
                withIntermediateDirectories: true
            )
        }
        XCTAssertEqual(ModelAssets.directorySize(at: root), 0)
        XCTAssertFalse(ModelAssets.whisperModelIsComplete(at: root))
    }

    func testModelStorageMakesStableLocalIDs() {
        XCTAssertEqual(ModelAssets.makeLocalID(
            prefix: "llm",
            folderName: "Qwen",
            existing: []
        ), "local/llm-Qwen")
        XCTAssertEqual(ModelAssets.makeLocalID(
            prefix: "whisper",
            folderName: "",
            existing: []
        ), "local/whisper-model")
        XCTAssertEqual(ModelAssets.makeLocalID(
            prefix: "llm",
            folderName: "Qwen",
            existing: ["local/llm-Qwen"]
        ), "local/llm-Qwen-2")
        XCTAssertEqual(ModelAssets.makeLocalID(
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

        XCTAssertEqual(ModelAssets.directorySize(at: root), 20)
        XCTAssertEqual(ModelAssets.directorySize(at: root.appendingPathComponent("missing")), 0)
    }


    func testModelStorageRequiresWeightsBeforeLLMIsComplete() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
        XCTAssertFalse(ModelAssets.llmRepoIsComplete(at: root))

        try Data("weights".utf8).write(to: root.appendingPathComponent("model.safetensors"))
        XCTAssertTrue(ModelAssets.llmRepoIsComplete(at: root))
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
        XCTAssertFalse(ModelAssets.llmRepoIsComplete(at: root))

        try Data("two".utf8).write(to: root.appendingPathComponent("model-00002-of-00002.safetensors"))
        XCTAssertTrue(ModelAssets.llmRepoIsComplete(at: root))
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
        XCTAssertFalse(ModelAssets.whisperModelIsComplete(at: root))

        for name in ["AudioEncoder", "TextDecoder"] {
            let component = root.appendingPathComponent("\(name).mlmodelc")
            try FileManager.default.createDirectory(
                at: component,
                withIntermediateDirectories: true
            )
            try Data("model".utf8).write(to: component.appendingPathComponent("model.bin"))
        }
        XCTAssertTrue(ModelAssets.whisperWeightsAreComplete(at: root))
        XCTAssertFalse(ModelAssets.whisperModelIsComplete(at: root), "Weights without a local tokenizer need repair")
    }

}
