import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import UtterContracts

extension RemoteLLMClient {
    // MARK: - OpenAI-compatible format

    func generateOpenAI(
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

        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        try validateHTTP(response, data: data)

        return try RemoteLLMResponseText.openAI(from: data)
    }

    // MARK: - Anthropic Messages format

    func generateAnthropic(
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

        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        try validateHTTP(response, data: data)

        return try RemoteLLMResponseText.anthropic(from: data)
    }

    // MARK: - Shared

    func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RemoteLLMError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw RemoteLLMError.requestFailed("HTTP \(http.statusCode): \(body)")
        }
    }
}
