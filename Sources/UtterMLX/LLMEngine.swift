import UtterContracts
import Foundation
import MLXLLM
import MLXLMCommon
import MLX

package actor LLMEngine {
    private let files: any ModelFilesService
    private var closed = false
    private var modelLoadAttempted = false
    private let log: Log

    package init(files: any ModelFilesService, log: Log) {
        self.files = files
        self.log = log
    }

    private var container: ModelContainer?
    private var currentModelID: String?
    private var currentModelRevision: String?

    package func loadModel(id: String, modelURL: URL? = nil) async throws {
        try Task.checkCancellation()
        guard !closed else { throw GenerationServiceError.unsupportedOperation }

        log.info("[LLMEngine] loading model: \(id)")
        let t0 = CFAbsoluteTimeGetCurrent()

        guard let localURL = modelURL ?? files.installedTextModelURL(id) else {
            throw LLMError.modelNotDownloaded
        }
        let revision = ModelLocationLease.identity(localURL)
        if currentModelID == id, currentModelRevision == revision, container != nil { return }
        modelLoadAttempted = true
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: localURL,
            using: MLXModelLoading.tokenizerLoader
        )

        try Task.checkCancellation()
        guard !closed else { throw GenerationServiceError.unsupportedOperation }
        container = loaded
        currentModelID = id
        currentModelRevision = revision
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        log.info("[LLMEngine] model loaded in \(String(format: "%.1f", elapsed))s")
    }

    package func generate(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) async throws -> String {
        try Task.checkCancellation()
        guard !closed else { throw GenerationServiceError.unsupportedOperation }
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
        log.info("[LLMEngine] generated \(result.count) chars in \(String(format: "%.1f", elapsed))s")
        return result
    }

    package func benchmark(modelID: String, modelURL: URL? = nil) async throws -> ModelBenchmarkResult {
        let loadT0 = CFAbsoluteTimeGetCurrent()
        try await loadModel(id: modelID, modelURL: modelURL)
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

        log.info("[LLMEngine] benchmark: \(tokenCount) tokens in \(String(format: "%.1f", genTime))s = \(String(format: "%.1f", tps)) tok/s")

        return ModelBenchmarkResult(
            loadTimeSeconds: loadTime,
            generateTimeSeconds: genTime,
            outputTokenEstimate: tokenCount,
            tokensPerSecond: tps
        )
    }

    package var isLoaded: Bool { container != nil }

    package func close() {
        closed = true
        unload()
    }

    package func unload() {
        container = nil
        currentModelID = nil
        currentModelRevision = nil
        if modelLoadAttempted {
            modelLoadAttempted = false
            Memory.clearCache()
        }
    }

    /// Qwen3-family chat templates read `enable_thinking` from the template
    /// context — the official switch for suppressing `<think>` blocks. The old
    /// `/no_think` soft prefix is ignored by Qwen3.5 and only added prompt noise.
    package static func chatTemplateContext(modelID: String?) -> [String: any Sendable]? {
        guard let id = modelID?.lowercased(), id.contains("qwen3") else { return nil }
        return ["enable_thinking": false]
    }

    package static func modelConfiguration(for id: String) -> ModelConfiguration {
        let extraEOSTokens: Set<String> = id.lowercased().contains("gemma-4") ? ["<turn|>"] : []
        return ModelConfiguration(id: id, extraEOSTokens: extraEOSTokens)
    }
}
