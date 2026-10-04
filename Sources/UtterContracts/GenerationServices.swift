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
    package let frozenModel: ModelLocationLease?
    package let maxTokens: Int
    package let temperature: Double
    package let remote: RemoteGenerationConfiguration?

    package init(
        prompt: String, systemPrompt: String? = nil, modelID: String, modelURL: URL? = nil,
        maxTokens: Int = 2048, temperature: Double = 0.3, remote: RemoteGenerationConfiguration? = nil,
        frozenModel: ModelLocationLease? = nil
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.modelID = modelID
        self.modelURL = modelURL
        self.frozenModel = frozenModel
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.remote = remote
    }

    package func localModelURL(using files: any ModelFilesService) throws -> URL? {
        if let frozenModel { return try frozenModel.requireInstalledURL() }
        return modelURL ?? files.installedTextModelURL(modelID)
    }
}

package enum GenerationPurpose: Sendable { case inference, benchmark }

package protocol TextGenerationService: Sendable {
    func generate(_ request: TextGenerationRequest) async throws -> String
    func prepare(_ request: TextGenerationRequest) async throws
    var isLoaded: Bool { get async }
    func unload() async
    func benchmark(_ request: TextGenerationRequest) async throws -> ModelBenchmarkResult
    func validateModel(at url: URL) async throws
}

package enum GenerationServiceError: Error, Equatable {
    case unsupportedOperation, modelUnavailable, modelChanged
}

extension TextGenerationService {
    package func prepare(_ request: TextGenerationRequest) async throws { try Task.checkCancellation() }
    package var isLoaded: Bool { get async { true } }
    package func unload() async {}
    package func benchmark(_ request: TextGenerationRequest) async throws -> ModelBenchmarkResult {
        throw GenerationServiceError.unsupportedOperation
    }
    package func validateModel(at url: URL) async throws { throw GenerationServiceError.unsupportedOperation }
}

package enum GenerationServices {
    package static let providers = ServiceKey<any ProviderCatalog<GenerationPurpose, any TextGenerationService>>("generation.providers")
    package static let remote = ServiceKey<ProviderDescriptor>("generation.remote")
    package static let mlx = ServiceKey<ProviderDescriptor>("generation.mlx")
    package static let ane = ServiceKey<ProviderDescriptor>("generation.ane")
}
