import Foundation
import UtterRuntime
import UtterContracts
import UtterMediaContracts
import UtterMLX
import UtterANE
import UtterRemoteInference

@MainActor
final class LegacyGenerationCatalog<Value: Sendable>: ProviderCatalog {
    typealias Request = GenerationPurpose
    private let values: [String: Value]
    private let benchmarkValues: [String: Value]
    let descriptors: [ProviderDescriptor]

    nonisolated init(values: [String: Value], benchmarkValues: [String: Value] = [:]) {
        self.values = values
        self.benchmarkValues = benchmarkValues
        descriptors = values.keys.sorted().map { ProviderDescriptor(id: $0, displayName: $0) }
    }

    func register(_ definition: ProviderDefinition<GenerationPurpose, Value>, scope: PluginScope) throws {
        throw GenerationServiceError.unsupportedOperation
    }

    func create(id: String, request: GenerationPurpose) async throws -> Value {
        try Task.checkCancellation()
        if request == .benchmark, let value = benchmarkValues[id] { return value }
        guard let value = values[id] else { throw ProviderCatalogError.unknownIdentifier(id) }
        return value
    }
}

struct LegacyGenerationServices {
    let text: any ProviderCatalog<GenerationPurpose, any TextGenerationService>
    let image: any ProviderCatalog<GenerationPurpose, any ImageGenerationService>

    init(access: any ModelResourceAccess, files: any ModelFilesService, log: UtterContracts.Log) {
        let mlx = MLXGenerationService(files: files, access: access, log: log)
        let ane = ANEGenerationService(files: files, access: access, log: log)
        let remote = RemoteLLMClient(transport: URLSessionRemoteTransport(), log: log)
        let benchmark = MLXGenerationService(files: files, access: access, log: log)
        text = LegacyGenerationCatalog<any TextGenerationService>(
            values: ["mlx": mlx, "generation.mlx": mlx, "espresso": ane, "generation.ane": ane, "remote": remote, "generation.remote": remote],
            benchmarkValues: ["mlx": benchmark, "generation.mlx": benchmark]
        )
        let vlm = MLXImageGenerationService(files: files, access: access, log: log)
        image = LegacyGenerationCatalog<any ImageGenerationService>(values: ["generation.mlx-image": vlm])
    }
}
