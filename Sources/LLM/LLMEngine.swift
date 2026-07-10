import Foundation
import MLXLLM
import MLXLMCommon
import MLX

actor LLMEngine {
    private var container: ModelContainer?
    private var currentModelID: String?

    func loadModel(
        id: String,
        estimatedDownloadBytes: Int64? = nil,
        progress: (@Sendable (DownloadProgressInfo) -> Void)? = nil
    ) async throws {
        if currentModelID == id, container != nil { return }

        Log.info("[LLMEngine] loading model: \(id)")
        let t0 = CFAbsoluteTimeGetCurrent()

        if let localURL = ModelStorage.localLLMURL(id) {
            container = try await LLMModelFactory.shared.loadContainer(
                from: localURL,
                using: MLXModelLoading.tokenizerLoader
            )
            progress?(DownloadProgressInfo(
                fraction: 1,
                elapsedSeconds: CFAbsoluteTimeGetCurrent() - t0,
                completedBytes: 0,
                totalBytes: 0,
                speedBytesPerSecond: 0
            ))
        } else {
            let estimatedTotalBytes = estimatedDownloadBytes ?? 0
            let repoDir = ModelStorage.hubModelRepoDir(id)
            let tracker = DownloadProgressTracker(initialBytes: ModelStorage.directorySize(at: repoDir))
            let config = Self.modelConfiguration(for: id)
            container = try await LLMModelFactory.shared.loadContainer(
                from: MLXModelLoading.downloader,
                using: MLXModelLoading.tokenizerLoader,
                configuration: config
            ) { p in
                let completedBytes = ModelStorage.directorySize(at: repoDir)
                progress?(tracker.update(
                    completedBytes: completedBytes,
                    totalBytes: estimatedTotalBytes,
                    fraction: p.fractionCompleted
                ))
            }
        }

        currentModelID = id
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Log.info("[LLMEngine] model loaded in \(String(format: "%.1f", elapsed))s")
    }

    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) async throws -> String {
        guard let container else {
            throw LLMError.modelNotLoaded
        }

        let t0 = CFAbsoluteTimeGetCurrent()

        let params = GenerateParameters(maxTokens: maxTokens, temperature: Float(temperature))
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: params,
            additionalContext: Self.chatTemplateContext(modelID: currentModelID)
        )
        let result = try await session.respond(to: prompt)

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Log.info("[LLMEngine] generated \(result.count) chars in \(String(format: "%.1f", elapsed))s")
        return result
    }

    struct BenchmarkResult: Sendable {
        let loadTimeSeconds: Double
        let generateTimeSeconds: Double
        let outputTokenEstimate: Int
        let tokensPerSecond: Double
    }

    func benchmark(modelID: String) async throws -> BenchmarkResult {
        let loadT0 = CFAbsoluteTimeGetCurrent()
        try await loadModel(id: modelID)
        let loadTime = CFAbsoluteTimeGetCurrent() - loadT0

        guard let container else { throw LLMError.modelNotLoaded }

        let testPrompt = "将以下口述内容整理为书面文字：嗯那个就是我觉得我们首先应该把这个方案重新梳理一下然后呢第二个就是要确认一下时间节点第三呢就是把预算也算一下"
        let systemPrompt = "你是语音转文字后处理引擎。直接输出整理后的文本，不要任何解释。"
        let params = GenerateParameters(maxTokens: 256, temperature: 0.3)
        let genT0 = CFAbsoluteTimeGetCurrent()

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": testPrompt],
        ]
        let lmInput = try await container.prepare(
            input: .init(
                messages: messages,
                additionalContext: Self.chatTemplateContext(modelID: modelID)
            )
        )
        let stream = try await container.generate(input: lmInput, parameters: params)

        var tokenCount = 0
        for await generation in stream {
            if let info = generation.info {
                tokenCount = info.generationTokenCount
            }
        }

        let genTime = CFAbsoluteTimeGetCurrent() - genT0
        let tps = genTime > 0 ? Double(tokenCount) / genTime : 0

        Log.info("[LLMEngine] benchmark: \(tokenCount) tokens in \(String(format: "%.1f", genTime))s = \(String(format: "%.1f", tps)) tok/s")

        return BenchmarkResult(
            loadTimeSeconds: loadTime,
            generateTimeSeconds: genTime,
            outputTokenEstimate: tokenCount,
            tokensPerSecond: tps
        )
    }

    var isLoaded: Bool { container != nil }

    func unload() {
        container = nil
        currentModelID = nil
    }

    /// Qwen3-family chat templates read `enable_thinking` from the template
    /// context — the official switch for suppressing `<think>` blocks. The old
    /// `/no_think` soft prefix is ignored by Qwen3.5 and only added prompt noise.
    static func chatTemplateContext(modelID: String?) -> [String: any Sendable]? {
        guard let id = modelID?.lowercased(), id.contains("qwen3") else { return nil }
        return ["enable_thinking": false]
    }

    static func modelConfiguration(for id: String) -> ModelConfiguration {
        let extraEOSTokens: Set<String> = id.lowercased().contains("gemma-4") ? ["<turn|>"] : []
        return ModelConfiguration(id: id, extraEOSTokens: extraEOSTokens)
    }
}

enum LLMError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "LLM 模型未加载"
        }
    }
}
