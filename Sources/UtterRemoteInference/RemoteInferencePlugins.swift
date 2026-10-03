import UtterContracts
import UtterRuntime

@MainActor
package enum RemoteInferencePlugins {
    package static func text() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "generation.remote",
            requires: [GenerationServices.providers.required, IntegrationServices.diagnostics.required],
            provides: [GenerationServices.remote.reference]
        )) { context, _ in
            let providers = try context.require(GenerationServices.providers)
            let client = RemoteLLMClient(transport: URLSessionRemoteTransport(), log: Log(service: try context.require(IntegrationServices.diagnostics)))
            try context.scope.onDispose { await client.shutdown() }
            let descriptor = ProviderDescriptor(id: "generation.remote", legacyIDs: ["remote"], displayName: L("model.family.remote"))
            try providers.register(ProviderDefinition(descriptor: descriptor) { _ in client }, scope: context.scope)
            try context.provide(GenerationServices.remote, value: descriptor)
        }
    }
}
