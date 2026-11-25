import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import MLXLMCommon
import MLXNN
import Tokenizers

package struct Audio8ASRGenerationResult {
    package let text: String
    package let modelTime: Double
    package let peakMemoryGB: Double
}

package final class Audio8ASRInferenceModel: Module {
    package let config: Audio8ASRConfiguration

    @ModuleInfo(key: "audio_encoder") var audioEncoder: Qwen3ASRAudioEncoder
    @ModuleInfo(key: "language_model") var languageModel: Audio8LanguageModel
    @ModuleInfo(key: "audio_mlp_tower") var audioMlpTower: Audio8MlpTower
    @ModuleInfo(key: "audio_projector") var audioProjector: Audio8Projector

    package var tokenizer: (any Tokenizers.Tokenizer)?

    package init(config: Audio8ASRConfiguration) throws {
        try config.validate()
        self.config = config
        self._audioEncoder.wrappedValue = Qwen3ASRAudioEncoder(config.audioConfig)
        self._languageModel.wrappedValue = Audio8LanguageModel(config)
        self._audioMlpTower.wrappedValue = Audio8MlpTower(
            dimensions: config.audioConfig.outputDim,
            layerCount: config.qwen3ASRMlpTowerLayers,
            intermediateDimensions: config.qwen3ASRMlpTowerHiddenSize > 0
                ? config.qwen3ASRMlpTowerHiddenSize
                : config.audioConfig.outputDim * 4
        )
        self._audioProjector.wrappedValue = Audio8Projector(
            inputDimensions: config.audioConfig.outputDim,
            outputDimensions: config.hiddenSize
        )
        super.init()
    }

    package static func fromModelDirectory(_ directory: URL) async throws -> Audio8ASRInferenceModel {
        let configData: Data
        do {
            configData = try Data(contentsOf: directory.appendingPathComponent("config.json"))
        } catch {
            throw Audio8ASRError.invalidConfiguration("config.json is missing or unreadable")
        }
        let config: Audio8ASRConfiguration
        do {
            config = try JSONDecoder().decode(Audio8ASRConfiguration.self, from: configData)
        } catch {
            throw Audio8ASRError.invalidConfiguration("config.json is not a valid Audio8 configuration")
        }
        let model = try Audio8ASRInferenceModel(config: config)

        let weightsURL = directory.appendingPathComponent("model.safetensors")
        guard (try? weightsURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 0 else {
            throw Audio8ASRError.missingWeights(["model.safetensors"])
        }
        do {
            let rawWeights = try MLX.loadArrays(url: weightsURL)
            let sanitized = sanitizeWeights(rawWeights)
            try model.update(parameters: ModuleParameters.unflattened(sanitized), verify: .all)
            eval(model)
            model.tokenizer = try await AutoTokenizer.from(modelFolder: directory)
            return model
        } catch let error as Audio8ASRError {
            throw error
        } catch {
            throw Audio8ASRError.invalidWeights(error.localizedDescription)
        }
    }

    package static func sanitizeWeights(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        var result: [String: MLXArray] = [:]
        for (key, value) in weights {
            let mappedKey = key
                .replacingOccurrences(of: "audio_projector.0.", with: "audio_projector.norm.")
                .replacingOccurrences(of: "audio_projector.1.", with: "audio_projector.linear.")
            if mappedKey.hasPrefix("audio_encoder.conv2d"), mappedKey.hasSuffix(".weight"), value.ndim == 4 {
                result[mappedKey] = value.transposed(0, 2, 3, 1)
            } else {
                result[mappedKey] = value
            }
        }
        return result
    }

    package func makeCache() -> [KVCache] {
        (0..<config.numHiddenLayers).map { _ in KVCacheSimple() }
    }

    package func preprocessAudio(_ audio: MLXArray) -> (MLXArray, MLXArray, Int) {
        let mel = Audio8AudioAdapterMath.melSpectrogram(
            audio: audio,
            sampleRate: 16_000,
            nFft: 400,
            hopLength: 160,
            melBins: config.audioConfig.numMelBins
        )
        let inputFeatures = mel.transposed(1, 0).expandedDimensions(axis: 0)
        let frameCount = mel.dim(0)
        let mask = MLX.ones([1, frameCount]).asType(.int32)
        let audioTokenCount = Self.audioTokenCount(sampleCount: audio.dim(0), mergeFactor: config.mergeFactor)
        return (inputFeatures, mask, audioTokenCount)
    }

    package func audioFeatures(inputFeatures: MLXArray, featureAttentionMask: MLXArray, tokenCount: Int) throws -> MLXArray {
        let encoded = audioEncoder(inputFeatures, featureAttentionMask: featureAttentionMask)
        let conditioned = audioMlpTower(encoded)
        let merged = try Audio8AudioAdapterMath.mergeAudioFrames(
            features: conditioned,
            audioTokenCount: tokenCount
        )
        return audioProjector(merged)
    }

    package func mergeAudioFeatures(
        inputsEmbeds: MLXArray,
        audioFeatures: MLXArray,
        inputIds: MLXArray
    ) -> MLXArray {
        let flatMask = (inputIds .== MLXArray(Int32(config.audioTokenID))).reshaped(-1)
        let hiddenDim = inputsEmbeds.dim(2)
        let flatEmbeds = inputsEmbeds.reshaped(-1, hiddenDim)
        let maskValues = flatMask.asType(.int32).asArray(Int32.self)
        guard let firstAudioPosition = maskValues.firstIndex(where: { $0 != 0 }) else {
            return inputsEmbeds
        }
        let replacementCount = min(audioFeatures.dim(0), maskValues.filter { $0 != 0 }.count)
        let endAudioPosition = firstAudioPosition + replacementCount

        var parts: [MLXArray] = []
        if firstAudioPosition > 0 {
            parts.append(flatEmbeds[0..<firstAudioPosition])
        }
        parts.append(audioFeatures[0..<replacementCount])
        if endAudioPosition < flatEmbeds.dim(0) {
            parts.append(flatEmbeds[endAudioPosition..<flatEmbeds.dim(0)])
        }
        return MLX.concatenated(parts, axis: 0)
            .reshaped(inputsEmbeds.dim(0), inputsEmbeds.dim(1), hiddenDim)
    }

    package func callAsFunction(inputsEmbeds: MLXArray, cache: [KVCache]?) -> MLXArray {
        languageModel(inputsEmbeds: inputsEmbeds, cache: cache)
    }

    package static func promptText(numAudioTokens: Int) -> String {
        "<|user|><|begin_of_audio|>"
            + String(repeating: "<|audio|>", count: numAudioTokens)
            + "<|end_of_audio|>Please transcribe this audio.<|assistant|>"
    }

    package static func audioTokenCount(sampleCount: Int, mergeFactor: Int) -> Int {
        let melFrames = sampleCount / 160
        return max(1, ((melFrames + 1) / 2) / max(mergeFactor, 1))
    }

    package func buildPrompt(numAudioTokens: Int) throws -> MLXArray {
        guard let tokenizer else { throw Audio8ASRError.invalidConfiguration("tokenizer is not loaded") }
        let prefix = tokenizer.encode(text: "<|user|><|begin_of_audio|>", addSpecialTokens: false)
        let suffix = tokenizer.encode(
            text: "<|end_of_audio|>Please transcribe this audio.<|assistant|>",
            addSpecialTokens: false
        )
        let ids = prefix + Array(repeating: config.audioTokenID, count: numAudioTokens) + suffix
        return MLXArray(ids.map { Int32($0) }).expandedDimensions(axis: 0)
    }

    package func generate(
        audio: MLXArray,
        hotwords: [String] = [],
        maxTokens: Int = 128
    ) throws -> Audio8ASRGenerationResult {
        guard let tokenizer else { throw Audio8ASRError.invalidConfiguration("tokenizer is not loaded") }
        let started = Date()
        let (inputFeatures, featureAttentionMask, audioTokenCount) = preprocessAudio(audio)
        let promptIDs = try buildPrompt(numAudioTokens: audioTokenCount)
        let features = try audioFeatures(
            inputFeatures: inputFeatures,
            featureAttentionMask: featureAttentionMask,
            tokenCount: audioTokenCount
        )
        eval(features)

        let embeddedPrompt = languageModel.model.embedTokens(promptIDs)
        let inputsEmbeds = mergeAudioFeatures(
            inputsEmbeds: embeddedPrompt,
            audioFeatures: features.asType(embeddedPrompt.dtype),
            inputIds: promptIDs
        )
        let cache = makeCache()
        let initialLogits = callAsFunction(inputsEmbeds: inputsEmbeds, cache: cache)
        var lastLogits = initialLogits[0..., -1, 0...].reshaped(-1)

        let tokenizedHotwords = Audio8HotwordLogits.tokenizedPhrases(hotwords, tokenizer: tokenizer)
        let trie = tokenizedHotwords.isEmpty ? nil : Audio8HotwordTrie(tokenizedPhrases: tokenizedHotwords)

        let endOfTextTokenID = 151643

        var generated: [Int] = []
        for tokenIndex in 0..<maxTokens {
            try Task.checkCancellation()
            let boosted = Audio8HotwordLogits.applyBoosts(
                to: lastLogits,
                generatedTokens: generated,
                trie: trie
            )
            let token = boosted.argMax().item(Int.self)
            if token == config.eosTokenID || token == endOfTextTokenID {
                break
            }
            generated.append(token)
            guard tokenIndex < maxTokens - 1 else { break }

            let nextInput = MLXArray([Int32(token)]).expandedDimensions(axis: 0)
            let nextEmbeds = languageModel.model.embedTokens(nextInput)
            let logits = callAsFunction(inputsEmbeds: nextEmbeds, cache: cache)
            lastLogits = logits[0..., -1, 0...].reshaped(-1)
        }

        let text = tokenizer.decode(tokens: generated, skipSpecialTokens: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Audio8ASRGenerationResult(
            text: text,
            modelTime: Date().timeIntervalSince(started),
            peakMemoryGB: Double(Memory.peakMemory) / 1_073_741_824
        )
    }
}
