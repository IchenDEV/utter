import UtterContracts
import UtterRuntime

@MainActor
extension RemoteInferencePlugins {
    package static func connection() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "generation.connection", requires: [
            GenerationServices.providers.required, GenerationServices.remote.required
        ], provides: [GenerationServices.connection.reference])) { context, _ in
            try context.provide(GenerationServices.connection, value: RegisteredRemoteConnection(
                providers: try context.require(GenerationServices.providers),
                providerID: try context.require(GenerationServices.remote).id, scope: context.scope))
        }
    }
}

@MainActor
private final class RegisteredRemoteConnection: RemoteConnectionService {
    let providers: any ProviderCatalog<GenerationPurpose, any TextGenerationService>
    let providerID: String
    let scope: PluginScope
    init(providers: any ProviderCatalog<GenerationPurpose, any TextGenerationService>, providerID: String, scope: PluginScope) {
        self.providers = providers; self.providerID = providerID; self.scope = scope
    }
    func test(configuration: RemoteGenerationConfiguration, modelID: String) async throws {
        try await scope.run {
            let provider = try await self.providers.create(id: self.providerID, request: .inference)
            _ = try await provider.generate(TextGenerationRequest(prompt: "Hi", modelID: modelID,
                maxTokens: 10, remote: configuration))
        }
    }
}
