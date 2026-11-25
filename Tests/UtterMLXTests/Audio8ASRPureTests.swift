import XCTest
import Foundation
@testable import UtterMLX

final class Audio8ASRPureTests: XCTestCase {
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

    func testHotwordTrieBoostsStartsAndSuffixContinuations() {
        let trie = Audio8HotwordTrie(tokenizedPhrases: [[10, 11, 12], [20, 21]])
        XCTAssertEqual(trie.candidateBoosts(generatedTokens: []), [10: 6, 20: 6])
        XCTAssertEqual(trie.candidateBoosts(generatedTokens: [99, 10]), [10: 6, 20: 6, 11: 8])
        XCTAssertEqual(trie.candidateBoosts(generatedTokens: [10, 11]), [10: 6, 20: 6, 12: 8])
        XCTAssertEqual(trie.candidateBoosts(generatedTokens: [10, 99]), [10: 6, 20: 6])
    }

    static let configJSON = Data(#"""
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
