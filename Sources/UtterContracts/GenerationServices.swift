import Foundation
import UtterRuntime

package struct RemoteGenerationConfiguration: Sendable {
    package let baseURL: String
    package let apiKey: String
    package let provider: RemoteProvider

    package init(baseURL: String, apiKey: String, provider: RemoteProvider) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.provider = provider
    }
}

package struct TextGenerationRequest: Sendable {
    package let prompt: String
    package let systemPrompt: String?
    package let modelID: String
    package let modelURL: URL?
    package let maxTokens: Int
    package let temperature: Double
    package let remote: RemoteGenerationConfiguration?

    package init(
        prompt: String, systemPrompt: String? = nil, modelID: String, modelURL: URL? = nil,
        maxTokens: Int = 2048, temperature: Double = 0.3, remote: RemoteGenerationConfiguration? = nil
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.modelID = modelID
        self.modelURL = modelURL
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.remote = remote
    }
}

package enum GenerationPurpose: Sendable { case inference, benchmark }

package protocol TextGenerationService: Sendable {
    func generate(_ request: TextGenerationRequest) async throws -> String
}

package enum GenerationServices {
    package static let providers = ServiceKey<any ProviderCatalog<GenerationPurpose, any TextGenerationService>>("generation.providers")
    package static let remote = ServiceKey<ProviderDescriptor>("generation.remote")
}
