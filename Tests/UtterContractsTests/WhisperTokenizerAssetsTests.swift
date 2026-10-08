import XCTest
@testable import UtterContracts

final class WhisperTokenizerAssetsTests: XCTestCase {
    func testMissingAndMalformedAssetsCannotFallBackToAnImplicitDownload() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try WhisperTokenizerAssets.read(at: directory, expectedModel: "large-v3"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("tokenizer.json"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("tokenizer_config.json"))
        XCTAssertThrowsError(try WhisperTokenizerAssets.read(at: directory, expectedModel: "large-v3"))
    }

    func testMultilingualAndEnglishVocabularyFamiliesAndVariantMismatch() throws {
        for model in ["base", "base.en", "large-v3"] {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            try writeTokenizer(model, at: directory)
            let assets = try WhisperTokenizerAssets.read(at: directory, expectedModel: model)
            XCTAssertEqual(assets.repository, "openai/whisper-" + model)
            XCTAssertEqual(assets.vocabularySize, model == "base.en" ? 51864 : model == "large-v3" ? 51866 : 51865)
            XCTAssertThrowsError(try WhisperTokenizerAssets.read(at: directory, expectedModel: "small"))
        }
    }

    func testTurboUsesTheLargeV3TokenizerAndCorruptNestedAssetsAreNotBypassed() throws {
        XCTAssertEqual(WhisperTokenizerAssets.repository(for: "openai_whisper-large-v3_turbo"), "openai/whisper-large-v3")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeTokenizer("large-v3", at: directory)
        XCTAssertNoThrow(try WhisperTokenizerAssets.read(at: directory, expectedModel: "large-v3-turbo"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(WhisperTokenizerAssets.directoryName), withIntermediateDirectories: true)
        XCTAssertThrowsError(try WhisperTokenizerAssets.read(at: directory, expectedModel: "large-v3-turbo"))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeTokenizer(_ model: String, at directory: URL) throws {
        let size = model == "base.en" ? 51864 : model == "large-v3" ? 51866 : 51865
        let end = model == "base.en" ? 50256 : 50257
        var vocabulary = Dictionary(uniqueKeysWithValues: (0..<size).map { ("token-\($0)", $0) })
        let special = ["<|endoftext|>", "<|startoftranscript|>", "<|en|>", "<|zh|>", "<|transcribe|>", "<|translate|>", "<|startofprev|>", model == "large-v3" ? "<|nospeech|>" : "<|nocaptions|>", "<|notimestamps|>", "<|0.00|>", "<|30.00|>"]
        for (offset, text) in special.enumerated() { vocabulary.removeValue(forKey: "token-\(end + offset)"); vocabulary[text] = end + offset }
        try JSONSerialization.data(withJSONObject: ["model": ["type": "BPE", "vocab": vocabulary, "merges": ["a b"]], "added_tokens": []])
            .write(to: directory.appendingPathComponent("tokenizer.json"))
        try JSONSerialization.data(withJSONObject: ["tokenizer_class": "WhisperTokenizer", "_name_or_path": "openai/whisper-" + model])
            .write(to: directory.appendingPathComponent("tokenizer_config.json"))
    }
}
