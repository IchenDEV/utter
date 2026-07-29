import Foundation

enum RemoteLLMError: LocalizedError {
    case noAPIKey
    case noBaseURL
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API key not configured"
        case .noBaseURL: return "Base URL not configured"
        case .requestFailed(let msg): return "Request failed: \(msg)"
        case .invalidResponse: return "Invalid response from server"
        }
    }
}

actor RemoteLLMClient {
    func generate(
        prompt: String,
        systemPrompt: String?,
        baseURL: String,
        apiKey: String,
        model: String,
        provider: RemoteProvider = .custom,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw RemoteLLMError.noAPIKey }

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
            guard let retryTokens = Self.retryTokenBudget(
                maxTokens: maxTokens,
                failureMessage: message
            ) else {
                throw RemoteLLMError.requestFailed(message)
            }
            Log.info(
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

    nonisolated static func retryTokenBudget(
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

    // MARK: - OpenAI-compatible format

    private func generateOpenAI(
        prompt: String,
        systemPrompt: String?,
        baseURL: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmedBase + "/chat/completions") else {
            throw RemoteLLMError.noBaseURL
        }

        var messages: [[String: String]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        return try RemoteLLMResponseText.openAI(from: data)
    }

    // MARK: - Anthropic Messages format

    private func generateAnthropic(
        prompt: String,
        systemPrompt: String?,
        baseURL: String,
        apiKey: String,
        model: String,
        apiVersion: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmedBase + "/messages") else {
            throw RemoteLLMError.noBaseURL
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "messages": [["role": "user", "content": prompt]],
        ]
        if let sys = systemPrompt, !sys.isEmpty {
            body["system"] = sys
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        return try RemoteLLMResponseText.anthropic(from: data)
    }

    // MARK: - Shared

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RemoteLLMError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw RemoteLLMError.requestFailed("HTTP \(http.statusCode): \(body)")
        }
    }
}
