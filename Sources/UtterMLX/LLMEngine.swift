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
    private var contextLimit: Int?

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
        let limit = try LocalGenerationBudget.contextLimit(configuration: Data(contentsOf: localURL.appendingPathComponent("config.json")))
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: MLXModelLoading.offlineDownloader,
            using: MLXModelLoading.tokenizerLoader,
            configuration: MLXModelLoading.configuration(id: id, directory: localURL)
        )

        try Task.checkCancellation()
        guard !closed else { throw GenerationServiceError.unsupportedOperation }
        container = loaded
        currentModelID = id
        currentModelRevision = revision
        contextLimit = limit
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
        var messages: [[String: String]] = []
        if let systemPrompt { messages.append(["role": "system", "content": systemPrompt]) }
        messages.append(["role": "user", "content": prompt])
        let inputTokens = try await container.prepare(input: .init(messages: messages,
            additionalContext: Self.chatTemplateContext(modelID: currentModelID))).text.tokens.size
        guard LocalGenerationBudget.allows(inputTokens: inputTokens, outputTokens: maxTokens, contextLimit: contextLimit) else {
            throw GenerationServiceError.contextLimitExceeded
        }
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

    package func benchmark(_ request: TextGenerationRequest, modelURL: URL?) async throws -> ModelBenchmarkResult {
        let loadStarted = ContinuousClock.now
        try await loadModel(id: request.modelID, modelURL: modelURL)
        let loadSeconds = milliseconds(loadStarted.duration(to: .now)) / 1000
        try Task.checkCancellation()
        guard let container else { throw LLMError.modelNotLoaded }
        let started = ContinuousClock.now
        var messages: [[String: String]] = []
        if let system = request.systemPrompt { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": request.prompt])
        let input = try await container.prepare(input: .init(messages: messages,
            additionalContext: Self.chatTemplateContext(modelID: request.modelID)))
        guard LocalGenerationBudget.allows(inputTokens: input.text.tokens.size, outputTokens: request.maxTokens,
                                          contextLimit: contextLimit) else {
            throw GenerationServiceError.contextLimitExceeded
        }
        let parameters = GenerateParameters(maxTokens: request.maxTokens, temperature: Float(request.temperature))
        let stream = try await container.generate(input: input, parameters: parameters)
        var tokens = 0
        for await generation in stream {
            try Task.checkCancellation()
            if let info = generation.info { tokens = info.generationTokenCount }
        }
        try Task.checkCancellation()
        let seconds = milliseconds(started.duration(to: .now)) / 1000
        return ModelBenchmarkResult(loadTimeSeconds: loadSeconds, generateTimeSeconds: seconds,
            outputTokenEstimate: tokens, tokensPerSecond: seconds > 0 ? Double(tokens) / seconds : 0)
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
        contextLimit = nil
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

}
