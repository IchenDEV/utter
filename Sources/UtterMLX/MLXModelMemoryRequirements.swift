import UtterContracts

extension MLXModelArtifacts {
    static let textMemoryRequirements: [String: ModelMemoryRequirements] = [
        "mlx-community/Qwen3.5-0.8B-MLX-4bit": .init(minimumGB: 2, recommendedGB: 4),
        "mlx-community/Qwen3.5-2B-4bit": .init(minimumGB: 4, recommendedGB: 6),
        "mlx-community/Qwen3.5-9B-5bit": .init(minimumGB: 10, recommendedGB: 12),
        "mlx-community/Qwen3-30B-A3B-4bit": .init(minimumGB: 24, recommendedGB: 32),
        "mlx-community/Qwen3.5-35B-A3B-4bit": .init(minimumGB: 28, recommendedGB: 40),
        "mlx-community/Qwen2.5-0.5B-Instruct-4bit": .init(minimumGB: 2, recommendedGB: 4),
        "mlx-community/Qwen2.5-1.5B-Instruct-4bit": .init(minimumGB: 2, recommendedGB: 4),
        "mlx-community/Qwen2.5-3B-Instruct-4bit": .init(minimumGB: 4, recommendedGB: 6),
        "mlx-community/Qwen3-0.6B-4bit": .init(minimumGB: 2, recommendedGB: 4),
        "mlx-community/Qwen3-1.7B-4bit": .init(minimumGB: 2, recommendedGB: 4),
        "mlx-community/Qwen3-4B-4bit": .init(minimumGB: 4, recommendedGB: 6),
        "mlx-community/gemma-4-e2b-it-4bit": .init(minimumGB: 6, recommendedGB: 8),
        "mlx-community/gemma-4-e4b-it-4bit": .init(minimumGB: 8, recommendedGB: 10),
        "mlx-community/gemma-3-1b-it-4bit": .init(minimumGB: 2, recommendedGB: 4),
        "mlx-community/gemma-3-4b-it-4bit": .init(minimumGB: 6, recommendedGB: 8),
        "mlx-community/gemma-3-12b-it-4bit": .init(minimumGB: 12, recommendedGB: 16),
        "mlx-community/Llama-4-Scout-17B-16E-Instruct-4bit": .init(minimumGB: 80, recommendedGB: 96),
        "mlx-community/Llama-4-Maverick-17B-128E-Instruct-4bit": .init(minimumGB: 256, recommendedGB: 384),
    ]
}
