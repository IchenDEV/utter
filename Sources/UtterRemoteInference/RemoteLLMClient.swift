import UtterContracts
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

package actor RemoteLLMClient: TextGenerationService {
    let transport: any RemoteTransport
    private let log: Log
    var closed = false
    private var inFlight = 0
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    package init(transport: any RemoteTransport, log: Log) {
        self.transport = transport
        self.log = log
    }

    package func generate(_ request: TextGenerationRequest) async throws -> String {
        guard let remote = request.remote else { throw RemoteLLMError.noBaseURL }
        return try await generate(
            prompt: request.prompt, systemPrompt: request.systemPrompt,
            baseURL: remote.baseURL, apiKey: remote.apiKey, model: request.modelID,
            provider: remote.provider, maxTokens: request.maxTokens, temperature: request.temperature
        )
    }

    package func shutdown() async {
        closed = true
        await transport.shutdown()
        guard inFlight > 0 else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    private func finishRequest() {
        inFlight -= 1
        guard inFlight == 0 else { return }
        let continuations = drainWaiters
        drainWaiters.removeAll()
        for continuation in continuations { continuation.resume() }
    }

    package func generate(
        prompt: String,
        systemPrompt: String?,
        baseURL: String,
        apiKey: String,
        model: String,
        provider: RemoteProvider = .custom,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) async throws -> String {
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        guard !apiKey.isEmpty else { throw RemoteLLMError.noAPIKey }
        inFlight += 1
        defer { finishRequest() }

        do {
            return try await generateOnce(
                prompt: prompt,
                systemPrompt: systemPrompt,
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                provider: provider,
                maxTokens: maxTokens,
                temperature: temperature
            )
        } catch RemoteLLMError.requestFailed(let message) {
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            guard let retryTokens = Self.retryTokenBudget(
                maxTokens: maxTokens,
                failureMessage: message
            ) else {
                throw RemoteLLMError.requestFailed(message)
            }
            log.info(
                "[RemoteLLM] retrying token-limit failure with \(retryTokens) max tokens"
            )
            return try await generateOnce(
                prompt: prompt,
                systemPrompt: systemPrompt,
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                provider: provider,
                maxTokens: retryTokens,
                temperature: temperature
            )
        } catch {
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            throw error
        }
    }

    private func generateOnce(
        prompt: String,
        systemPrompt: String?,
        baseURL: String,
        apiKey: String,
        model: String,
        provider: RemoteProvider,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        switch provider.apiFormat {
        case .anthropic:
            return try await generateAnthropic(
                prompt: prompt, systemPrompt: systemPrompt,
                baseURL: baseURL, apiKey: apiKey, model: model,
                apiVersion: provider.defaultApiVersion ?? "2023-06-01",
                maxTokens: maxTokens, temperature: temperature
            )
        case .openai:
            return try await generateOpenAI(
                prompt: prompt, systemPrompt: systemPrompt,
                baseURL: baseURL, apiKey: apiKey, model: model,
                maxTokens: maxTokens, temperature: temperature
            )
        }
    }

    package nonisolated static func retryTokenBudget(
        maxTokens: Int,
        failureMessage: String
    ) -> Int? {
        let message = failureMessage.lowercased()
        let indicatesUnsupportedParameter = [
            "unsupported parameter",
            "unknown parameter",
            "unrecognized parameter",
            "use max_completion_tokens",
        ].contains { message.contains($0) }
        guard !indicatesUnsupportedParameter else { return nil }

        if let statusRange = message.range(
            of: #"http\s+(\d{3})"#,
            options: .regularExpression
        ) {
            let status = Int(message[statusRange].filter(\.isNumber))
            guard status == 400 || status == 413 || status == 422 else {
                return nil
            }
        }

        let indicatesContextLimit = [
            "maximum context",
            "context length",
            "context_length",
            "too many tokens",
            "token limit",
            "max output",
            "maximum number of tokens",
        ].contains { message.contains($0) }
        let indicatesOutputBudgetLimit = message.contains("max_tokens")
            && ["must be less", "too large", "exceed", "limit"]
                .contains { message.contains($0) }
        guard indicatesContextLimit || indicatesOutputBudgetLimit else { return nil }

        let retryTokens = max(256, min(1_024, maxTokens / 2))
        return retryTokens < maxTokens ? retryTokens : nil
    }

}
