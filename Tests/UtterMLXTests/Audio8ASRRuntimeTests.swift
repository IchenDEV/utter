import XCTest
import Foundation
import MLX
@testable import UtterMLX

final class Audio8ASRRuntimeTests: XCTestCase {
    func testConfigurationDecodesAndValidatesPinnedDimensions() throws {
        let config = try JSONDecoder().decode(Audio8ASRConfiguration.self, from: Self.configJSON)
        XCTAssertEqual(config.modelType, "arkasr")
        XCTAssertEqual(config.hiddenSize, 512)
        XCTAssertEqual(config.numHiddenLayers, 8)
        XCTAssertEqual(config.numAttentionHeads, 8)
        XCTAssertEqual(config.numKeyValueHeads, 8)
        XCTAssertEqual(config.intermediateSize, 1408)
        XCTAssertEqual(config.audioTokenID, 151646)
        XCTAssertEqual(config.eosTokenID, 151645)
        XCTAssertEqual(config.mergeFactor, 4)
        XCTAssertEqual(config.audioConfig.dModel, 896)
        XCTAssertEqual(config.audioConfig.outputDim, 1024)
        XCTAssertEqual(config.audioConfig.encoderLayers, 18)
        XCTAssertEqual(config.audioConfig.encoderAttentionHeads, 14)
        XCTAssertEqual(config.audioConfig.encoderFfnDim, 3584)
        XCTAssertEqual(config.audioConfig.numMelBins, 128)
        XCTAssertNoThrow(try config.validate())
    }

    func testConfigurationRejectsWrongAudioTokenID() throws {
        var text = String(data: Self.configJSON, encoding: .utf8)!
        text = text.replacingOccurrences(of: "\"audio_token_id\": 151646", with: "\"audio_token_id\": 151647")
        let config = try JSONDecoder().decode(Audio8ASRConfiguration.self, from: Data(text.utf8))
        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertTrue(String(describing: error).contains("token ids"))
        }
    }

    func testAudioTokenCountUsesUpstreamMelFrameFormula() {
        XCTAssertEqual(Audio8ASRInferenceModel.audioTokenCount(sampleCount: 0, mergeFactor: 4), 1)
        XCTAssertEqual(Audio8ASRInferenceModel.audioTokenCount(sampleCount: 159, mergeFactor: 4), 1)
        XCTAssertEqual(Audio8ASRInferenceModel.audioTokenCount(sampleCount: 160, mergeFactor: 4), 1)
        XCTAssertEqual(Audio8ASRInferenceModel.audioTokenCount(sampleCount: 1_600, mergeFactor: 4), 1)
        XCTAssertEqual(Audio8ASRInferenceModel.audioTokenCount(sampleCount: 16_000, mergeFactor: 4), 12)
        XCTAssertEqual(Audio8ASRInferenceModel.audioTokenCount(sampleCount: 480_000, mergeFactor: 4), 375)
    }

    func testPromptTextMatchesUpstreamConversationFormat() {
        XCTAssertEqual(
            Audio8ASRInferenceModel.promptText(numAudioTokens: 3),
            "<|user|><|begin_of_audio|><|audio|><|audio|><|audio|>"
                + "<|end_of_audio|>Please transcribe this audio.<|assistant|>"
        )
    }

    func testMelFrontendUsesExactWhisperFrameCount() {
        let audio = MLXArray.zeros([48_000]).asType(.float32)
        let mel = Audio8AudioAdapterMath.melSpectrogram(
            audio: audio,
            sampleRate: 16_000,
            nFft: 400,
            hopLength: 160,
            melBins: 128
        )
        XCTAssertEqual(mel.shape, [300, 128])
    }

    func testAdaptiveAveragePoolMatchesReferenceBins() throws {
        let input = MLXArray((0..<5).map { Float($0) }).expandedDimensions(axis: 1)
        let pooled = Audio8AudioAdapterMath.adaptiveAveragePool1d(input, outputLength: 2)
        XCTAssertEqual(pooled.shape, [2, 1])
        XCTAssertEqual(pooled[0, 0].item(Float.self), 1.0, accuracy: 0.0001)
        XCTAssertEqual(pooled[1, 0].item(Float.self), 3.0, accuracy: 0.0001)
    }

    func testHotwordTrieBoostsStartsAndSuffixContinuations() {
        let trie = Audio8HotwordTrie(tokenizedPhrases: [[10, 11, 12], [20, 21]])
        XCTAssertEqual(trie.candidateBoosts(generatedTokens: []), [10: 6, 20: 6])
        XCTAssertEqual(trie.candidateBoosts(generatedTokens: [99, 10]), [10: 6, 20: 6, 11: 8])
        XCTAssertEqual(trie.candidateBoosts(generatedTokens: [10, 11]), [10: 6, 20: 6, 12: 8])
        XCTAssertEqual(trie.candidateBoosts(generatedTokens: [10, 99]), [10: 6, 20: 6])
    }

    func testHotwordBoostOnlyAppliesToTopK() {
        let trie = Audio8HotwordTrie(tokenizedPhrases: [[59]])
        var values = [Float](repeating: -10, count: 60)
        for index in 0..<50 { values[index] = Float(100 - index) }
        values[59] = -100
        let unchanged = Audio8HotwordLogits.applyBoosts(
            to: MLXArray(values), generatedTokens: [], trie: trie, topK: 50
        )
        XCTAssertEqual(unchanged[59].item(Float.self), -100, accuracy: 0.0001)

        values[59] = 99
        let boosted = Audio8HotwordLogits.applyBoosts(
            to: MLXArray(values), generatedTokens: [], trie: trie, topK: 50
        )
        XCTAssertEqual(boosted[59].item(Float.self), 105, accuracy: 0.0001)
    }



    func testLoaderRejectsMissingWeightsAsDamagedModelAssets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.configJSON.write(to: directory.appendingPathComponent("config.json"))

        do {
            _ = try await Audio8ASRInferenceModel.fromModelDirectory(directory)
            XCTFail("missing weights must not load")
        } catch Audio8ASRError.missingWeights(let keys) {
            XCTAssertEqual(keys, ["model.safetensors"])
        }
    }

    func testLoaderRejectsUnreadableWeightsAsDamagedModelAssets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.configJSON.write(to: directory.appendingPathComponent("config.json"))
        try Data("not-a-safetensor".utf8).write(to: directory.appendingPathComponent("model.safetensors"))

        do {
            _ = try await Audio8ASRInferenceModel.fromModelDirectory(directory)
            XCTFail("damaged weights must not load")
        } catch Audio8ASRError.invalidWeights(let message) {
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testWeightSanitizationTransposesConvWeightsToMLXLayout() {
        let weight = MLXArray.zeros([480, 1, 3, 3])
        let sanitized = Audio8ASRInferenceModel.sanitizeWeights([
            "audio_encoder.conv2d1.weight": weight,
            "audio_projector.0.weight": MLXArray.zeros([2]),
            "audio_projector.1.weight": MLXArray.zeros([2, 4]),
            "language_model.model.embed_tokens.weight": MLXArray.zeros([4, 2]),
        ])
        XCTAssertEqual(sanitized["audio_encoder.conv2d1.weight"]?.shape, [480, 3, 3, 1])
        XCTAssertNotNil(sanitized["audio_projector.norm.weight"])
        XCTAssertNotNil(sanitized["audio_projector.linear.weight"])
        XCTAssertNil(sanitized["audio_projector.0.weight"])
        XCTAssertEqual(sanitized["language_model.model.embed_tokens.weight"]?.shape, [4, 2])
    }

    func testMergeAudioFeaturesReplacesContiguousAudioPlaceholders() throws {
        let config = try JSONDecoder().decode(Audio8ASRConfiguration.self, from: Self.configJSON)
        let model = try Audio8ASRInferenceModel(config: config)
        let inputs = MLXArray((0..<40).map { Float($0) }).reshaped(1, 10, 4)
        let replacement = MLXArray((0..<12).map { Float(100 + $0) }).reshaped(3, 4)
        let ids = MLXArray([Int32(1), 151646, 151646, 151646, 2, 3, 4, 5, 6, 7]).expandedDimensions(axis: 0)
        let merged = model.mergeAudioFeatures(inputsEmbeds: inputs, audioFeatures: replacement, inputIds: ids)
        XCTAssertEqual(merged.shape, [1, 10, 4])
        XCTAssertEqual(merged[0, 0, 0].item(Float.self), 0, accuracy: 0.0001)
        XCTAssertEqual(merged[0, 1, 0].item(Float.self), 100, accuracy: 0.0001)
        XCTAssertEqual(merged[0, 3, 2].item(Float.self), 110, accuracy: 0.0001)
        XCTAssertEqual(merged[0, 4, 0].item(Float.self), 16, accuracy: 0.0001)
    }

    private static let configJSON = Data(#"""
    {
      "model_type": "arkasr",
      "hidden_size": 512,
      "num_hidden_layers": 8,
      "num_attention_heads": 8,
      "num_key_value_heads": 8,
      "intermediate_size": 1408,
      "vocab_size": 151936,
      "rms_norm_eps": 0.000001,
      "rope_theta": 1000000.0,
      "max_position_embeddings": 32768,
      "tie_word_embeddings": true,
      "audio_token_id": 151646,
      "eos_token_id": 151645,
      "merge_factor": 4,
      "qwen3_asr_mlp_tower_layers": 4,
      "qwen3_asr_mlp_tower_hidden_size": 4096,
      "qwen3_asr_audio_config": {
        "num_mel_bins": 128,
        "encoder_layers": 18,
        "encoder_attention_heads": 14,
        "encoder_ffn_dim": 3584,
        "d_model": 896,
        "attention_dropout": 0.0,
        "activation_function": "gelu",
        "max_source_positions": 1500,
        "n_window": 50,
        "output_dim": 1024,
        "n_window_infer": 800,
        "conv_chunksize": 500,
        "downsample_hidden_size": 480
      }
    }
    """#.utf8)
}
