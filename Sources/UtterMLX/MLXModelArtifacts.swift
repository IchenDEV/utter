import UtterContracts

package enum MLXModelArtifacts {
    package static var text: [ModelArtifact] {
        let rows: [(String, String, String, CatalogModelFamily?, CatalogModelTier)] = [
            // Qwen Family
            ("mlx-community/Qwen3.5-0.8B-MLX-4bit", "Qwen3.5 0.8B", L("model.qwen35_tiny"), .qwen, .recommended),
            ("mlx-community/Qwen3.5-2B-4bit", "Qwen3.5 2B", L("model.qwen35_fast"), .qwen, .recommended),
            ("mlx-community/Qwen3.5-9B-5bit", "Qwen3.5 9B", L("model.qwen35_quality"), .qwen, .recommended),
            ("mlx-community/Qwen3-30B-A3B-4bit", "Qwen3 30B-A3B", L("model.qwen3_moe"), .qwen, .recommended),
            ("mlx-community/Qwen3.5-35B-A3B-4bit", "Qwen3.5 35B-A3B", L("model.qwen35_moe"), .qwen, .standard),
            ("mlx-community/Qwen2.5-0.5B-Instruct-4bit", "Qwen2.5 0.5B", L("model.smallest"), .qwen, .legacy),
            ("mlx-community/Qwen2.5-1.5B-Instruct-4bit", "Qwen2.5 1.5B", L("model.balanced"), .qwen, .legacy),
            ("mlx-community/Qwen2.5-3B-Instruct-4bit", "Qwen2.5 3B", L("model.best_quality"), .qwen, .legacy),
            ("mlx-community/Qwen3-0.6B-4bit", "Qwen3 0.6B", L("model.qwen3_fast"), .qwen, .legacy),
            ("mlx-community/Qwen3-1.7B-4bit", "Qwen3 1.7B", L("model.qwen3_balanced"), .qwen, .legacy),
            ("mlx-community/Qwen3-4B-4bit", "Qwen3 4B", L("model.qwen3_quality"), .qwen, .legacy),

            // Gemma Family (Google)
            ("mlx-community/gemma-4-e2b-it-4bit", "Gemma 4 E2B", L("model.gemma4_edge"), .gemma, .recommended),
            ("mlx-community/gemma-4-e4b-it-4bit", "Gemma 4 E4B", L("model.gemma4_edge_quality"), .gemma, .standard),
            ("mlx-community/gemma-3-1b-it-4bit", "Gemma 3 1B", L("model.gemma_fast"), .gemma, .legacy),
            ("mlx-community/gemma-3-4b-it-4bit", "Gemma 3 4B", L("model.gemma_balanced"), .gemma, .legacy),
            ("mlx-community/gemma-3-12b-it-4bit", "Gemma 3 12B", L("model.gemma_quality"), .gemma, .legacy),

            // Llama Family (Meta)
            ("mlx-community/Llama-4-Scout-17B-16E-Instruct-4bit", "Llama 4 Scout", L("model.llama_balanced"), .llama, .recommended),
            ("mlx-community/Llama-4-Maverick-17B-128E-Instruct-4bit", "Llama 4 Maverick", L("model.llama_quality"), .llama, .standard),
        ]
        return rows.enumerated().map { index, row in
            ModelArtifact(id: row.0, kind: .llm, displayName: row.1, hint: row.2,
                          family: row.3, tier: row.4, rank: index)
        }
    }

    package static var qwen: [ModelArtifact] {
        let files = ["config.json", "model.safetensors", "model.safetensors.index.json", "preprocessor_config.json",
                     "tokenizer_config.json", "vocab.json", "merges.txt"]
        return [
            ModelArtifact(id: QwenASRModel.defaultID, kind: .asr, displayName: "Qwen3-ASR 1.7B",
                          hint: L("model.qwen3_asr_quality"), requiredFiles: files, rank: 0),
            ModelArtifact(id: QwenASRModel.confuciusR2T2ID, kind: .asr, displayName: "Confucius4-R2T2 8-bit",
                          hint: L("model.confucius_r2t2"), requiredFiles: files + ["LICENSE", "MODEL_LICENSE_zh", "NOTICE"], rank: 1),
        ]
    }
    package static var firered: [ModelArtifact] {
        [ModelArtifact(id: "mlx-community/FireRedASR2-AED-mlx", kind: .asr, displayName: "FireRedASR2-AED",
                       hint: L("model.firered_asr"), requiredFiles: ["config.json", "cmvn.json", "dict.txt", "model.safetensors"], rank: 2)]
    }
    package static var mega: [ModelArtifact] {
        [ModelArtifact(id: "mlx-community/Mega-ASR-6bit", kind: .asr, displayName: "Mega-ASR 6bit",
                       hint: L("model.mega_asr"), requiredFiles: ["config.json", "tokenizer_config.json"], rank: 3)]
    }
    package static var speechDescriptors: [ProviderDescriptor] {
        [ProviderDescriptor(id: "speech.qwen", legacyIDs: [SpeechEngineType.qwen3.rawValue], displayName: L("engine.qwen3_short"), artifacts: qwen),
         ProviderDescriptor(id: "speech.firered", legacyIDs: [SpeechEngineType.firered.rawValue], displayName: L("engine.firered_short"), artifacts: firered),
         ProviderDescriptor(id: "speech.mega", legacyIDs: [SpeechEngineType.megaASR.rawValue], displayName: L("engine.mega_short"), artifacts: mega)]
    }
    package static var speech: [ModelArtifact] { qwen + firered + mega }
}
