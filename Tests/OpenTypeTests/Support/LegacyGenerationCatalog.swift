import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterIngress
import Foundation
import UtterRuntime
import UtterContracts
import UtterMediaContracts
import UtterMLX
import UtterANE
import UtterRemoteInference

@MainActor
final class TestGenerationCatalog<Value: Sendable>: ProviderCatalog {
    typealias Request = GenerationPurpose
    private let values: [String: Value]
    private let benchmarkValues: [String: Value]
    private let unload: @MainActor (Value) async -> Void
    let descriptors: [ProviderDescriptor]

    nonisolated init(values: [String: Value], benchmarkValues: [String: Value] = [:],
                     descriptors: [ProviderDescriptor]? = nil, unload: @escaping @MainActor (Value) async -> Void = { _ in }) {
        self.values = values
        self.benchmarkValues = benchmarkValues
        self.descriptors = descriptors ?? values.keys.sorted().map { ProviderDescriptor(id: $0, displayName: $0) }
        self.unload = unload
    }

    func register(_ definition: ProviderDefinition<GenerationPurpose, Value>, scope: PluginScope) throws {
        throw GenerationServiceError.unsupportedOperation
    }

    func create(id: String, request: GenerationPurpose) async throws -> Value {
        try Task.checkCancellation()
        let key = try canonicalID(id)
        if request == .benchmark, let value = benchmarkValues[key] { return value }
        guard let value = values[key] else { throw ProviderCatalogError.unknownIdentifier(id) }
        return value
    }

    func reset(id: String) async throws {
        try Task.checkCancellation()
        let key = try canonicalID(id)
        guard let value = values[key] else { throw ProviderCatalogError.unknownIdentifier(id) }
        await unload(value)
        if let benchmark = benchmarkValues[key] { await unload(benchmark) }
    }

    private func canonicalID(_ id: String) throws -> String {
        guard let descriptor = descriptors.first(where: { $0.id == id || $0.legacyIDs.contains(id) }) else {
            throw ProviderCatalogError.unknownIdentifier(id)
        }
        return descriptor.id
    }
}

struct TestGenerationServices {
    let text: any ProviderCatalog<GenerationPurpose, any TextGenerationService>
    let image: any ProviderCatalog<GenerationPurpose, any ImageGenerationService>

    init(access: any ModelResourceAccess, files: any ModelFilesService, log: UtterContracts.Log) {
        let mlx = MLXGenerationService(files: files, access: access, log: log)
        let ane = ANEGenerationService(files: files, access: access, log: log)
        let remote = RemoteLLMClient(transport: URLSessionRemoteTransport(), log: log)
        let benchmark = MLXGenerationService(files: files, access: access, log: log)
        text = TestGenerationCatalog<any TextGenerationService>(
            values: ["generation.mlx": mlx, "generation.ane": ane, "generation.remote": remote],
            benchmarkValues: ["generation.mlx": benchmark],
            descriptors: [ProviderDescriptor(id: "generation.mlx", legacyIDs: ["mlx"], displayName: "MLX"),
                          ProviderDescriptor(id: "generation.ane", legacyIDs: ["espresso"], displayName: "ANE"),
                          ProviderDescriptor(id: "generation.remote", legacyIDs: ["remote"], displayName: "Remote")],
            unload: { await $0.unload() }
        )
        let vlm = MLXImageGenerationService(files: files, access: access, log: log)
        image = TestGenerationCatalog<any ImageGenerationService>(values: ["generation.mlx-image": vlm], unload: { await $0.unload() })
    }
}
