import UtterContracts
import UtterRuntime

@MainActor
package enum BuiltinCompositions {
    package static let shipped = CompositionDocument(bundles: ["desktop"])
    package static let recoveryIDs: Set<String> = ["data.settings", "data.credentials", "data.notifications",
                                                 "data.diagnostics", "data.configuration"]

    package static func bundles(_ registrations: [PluginRegistration]) -> [CompositionLayer] {
        [CompositionLayer("desktop", plugins: registrations.map { PluginConfigurationRow($0.descriptor.id) }),
         CompositionLayer("recovery", plugins: registrations.filter { recoveryIDs.contains($0.descriptor.id) }
            .map { PluginConfigurationRow($0.descriptor.id) })]
    }

    package static var providers: [ProviderBindingDescriptor] {
        let speech = ["apple", "whisper", "volc", "qwen", "firered", "mega"]
            .map { ProviderBindingDescriptor(capability: "speech", providerID: "speech." + $0, pluginID: "speech." + $0) }
        let text = ["mlx", "ane", "remote"].flatMap { name in
            ["text", "fallback"].map {
                ProviderBindingDescriptor(capability: $0, providerID: "generation." + name, pluginID: "generation." + name)
            }
        }
        let modes = ["direct", "formatting", "command", "translation", "edit"].map {
            ProviderBindingDescriptor(capability: "mode." + $0, providerID: "mode." + $0, pluginID: "mode." + $0)
        }
        return speech + text + modes + [ProviderBindingDescriptor(capability: "image",
            providerID: "generation.mlx-image", pluginID: "generation.mlx-image")]
    }

    package static func legacy(_ settings: SettingsValues) -> CompositionLayer {
        let speech: String
        switch settings.speechEngine {
        case .qwen3: speech = "speech.qwen"
        case .megaASR: speech = "speech.mega"
        default: speech = "speech." + settings.speechEngine.rawValue
        }
        let text = settings.useRemoteLLM ? "generation.remote"
            : settings.localLLMBackend == .espresso ? "generation.ane" : "generation.mlx"
        return CompositionLayer("legacy", bindings: ["speech": speech, "text": text])
    }
}
