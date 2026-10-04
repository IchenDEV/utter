import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension ModelPlugins {
    package static func lifecycle() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "models.lifecycle", requires: [
            DataServices.settings.required, DataServices.credentials.required, DataServices.configuration.optional,
            ModelServices.resourceAccess.required, ModelServices.files.required, ProcessingServices.models.required,
            SpeechServices.providers.required, GenerationServices.providers.required
        ], provides: [ModelServices.lifecycle.reference])) { context, _ in
            let service = ModelLifecycle(settings: try context.require(DataServices.settings),
                credentials: try context.require(DataServices.credentials), configuration: try context.optional(DataServices.configuration),
                access: try context.require(ModelServices.resourceAccess), files: try context.require(ModelServices.files),
                processing: try context.require(ProcessingServices.models), speech: try context.require(SpeechServices.providers),
                generation: try context.require(GenerationServices.providers), scope: context.scope)
            try context.scope.onRevoke { service.revoke() }
            try context.scope.onReady { _ = try context.scope.task { await service.preloadOnLaunch() } }
            try context.provide(ModelServices.lifecycle, value: service)
        }
    }
}
