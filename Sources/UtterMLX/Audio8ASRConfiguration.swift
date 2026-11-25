import Foundation
import UtterContracts
import MLXAudioSTT

package enum Audio8ASRError: Error, LocalizedError, Equatable {
    case notConfigured
    case invalidConfiguration(String)
    case missingWeights([String])
    case invalidWeights(String)
    case noAudioInput
    case audioTooLong
    case emptyRecognitionResult

    package var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L("error.audio8.notConfigured")
        case .invalidConfiguration(let message):
            return "Audio8 model configuration is invalid: \(message)"
        case .missingWeights(let keys):
            return "Audio8 weights are incomplete; missing \(keys.count) tensors: \(keys.prefix(8).joined(separator: ", "))"
        case .invalidWeights(let message):
            return "Audio8 weights are invalid: \(message)"
        case .noAudioInput:
            return L("error.audio8.noAudioInput")
        case .audioTooLong:
            return L("error.audio8.audioTooLong")
        case .emptyRecognitionResult:
            return L("error.audio8.emptyRecognitionResult")
        }
    }
}

package struct Audio8ASRConfiguration: Decodable {
    package let modelType: String
    package let hiddenSize: Int
    package let numHiddenLayers: Int
    package let numAttentionHeads: Int
    package let numKeyValueHeads: Int
    package let intermediateSize: Int
    package let vocabSize: Int
    package let rmsNormEps: Float
    package let ropeTheta: Float
    package let maxPositionEmbeddings: Int
    package let tieWordEmbeddings: Bool
    package let audioTokenID: Int
    package let eosTokenID: Int
    package let mergeFactor: Int
    package let qwen3ASRMlpTowerLayers: Int
    package let qwen3ASRMlpTowerHiddenSize: Int
    package let audioConfig: Qwen3AudioEncoderConfig

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case intermediateSize = "intermediate_size"
        case vocabSize = "vocab_size"
        case rmsNormEps = "rms_norm_eps"
        case ropeTheta = "rope_theta"
        case maxPositionEmbeddings = "max_position_embeddings"
        case tieWordEmbeddings = "tie_word_embeddings"
        case audioTokenID = "audio_token_id"
        case eosTokenID = "eos_token_id"
        case mergeFactor = "merge_factor"
        case qwen3ASRMlpTowerLayers = "qwen3_asr_mlp_tower_layers"
        case qwen3ASRMlpTowerHiddenSize = "qwen3_asr_mlp_tower_hidden_size"
        case audioConfig = "qwen3_asr_audio_config"
    }

    package func validate() throws {
        guard modelType == "arkasr" else {
            throw Audio8ASRError.invalidConfiguration("expected model_type arkasr, got \(modelType)")
        }
        guard hiddenSize == 512 else {
            throw Audio8ASRError.invalidConfiguration("expected hidden_size 512, got \(hiddenSize)")
        }
        guard numHiddenLayers == 8, numAttentionHeads == 8, numKeyValueHeads == 8, intermediateSize == 1408 else {
            throw Audio8ASRError.invalidConfiguration("unsupported decoder dimensions")
        }
        guard vocabSize == 151936 else {
            throw Audio8ASRError.invalidConfiguration("unsupported vocabulary size")
        }
        guard audioTokenID == 151646, eosTokenID == 151645 else {
            throw Audio8ASRError.invalidConfiguration("unsupported Audio8 token ids")
        }
        guard audioConfig.dModel == 896, audioConfig.outputDim == 1024, audioConfig.downsampleHiddenSize == 480,
              audioConfig.encoderLayers == 18, audioConfig.encoderAttentionHeads == 14,
              audioConfig.encoderFfnDim == 3584, audioConfig.numMelBins == 128 else {
            throw Audio8ASRError.invalidConfiguration("unsupported audio encoder dimensions")
        }
        guard mergeFactor == 4 else {
            throw Audio8ASRError.invalidConfiguration("unsupported audio adapter merge factor")
        }
        guard qwen3ASRMlpTowerLayers == 4 else {
            throw Audio8ASRError.invalidConfiguration("unsupported audio adapter layer count")
        }
        guard tieWordEmbeddings else {
            throw Audio8ASRError.invalidConfiguration("Audio8 requires tied embeddings")
        }
    }
}
