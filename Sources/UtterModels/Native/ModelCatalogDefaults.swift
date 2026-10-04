import Foundation
import UtterContracts

extension ModelCatalog {
    package static var defaultLLMModels: [(String, String, String, ModelFamily?, ModelTier)] {
        [
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
    }

    // MARK: - Display Name

}
