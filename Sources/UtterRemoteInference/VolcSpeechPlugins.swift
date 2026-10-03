import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension RemoteInferencePlugins {
    package static func speech() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "speech.volc",
            requires: [SpeechServices.providers.required, IntegrationServices.diagnostics.required],
            provides: [SpeechServices.volc.reference]
        )) { context, _ in
            let registry = try context.require(SpeechServices.providers)
            let cache = VolcProviderCache(log: Log(service: try context.require(IntegrationServices.diagnostics)))
            try context.scope.onDispose { await cache.close() }
            let descriptor = ProviderDescriptor(id: "speech.volc", legacyIDs: [SpeechEngineType.volc.rawValue], displayName: L("engine.volc_short"))
            try registry.register(ProviderDefinition(descriptor: descriptor) { request in try await cache.engine(request.selection) }, scope: context.scope)
            try context.provide(SpeechServices.volc, value: descriptor)
        }
    }
}

@MainActor
private final class VolcProviderCache {
    private let log: Log
    private var cached: (SpeechSelection, VolcSpeechEngine)?
    private var closed = false

    init(log: Log) { self.log = log }

    func engine(_ selection: SpeechSelection) async throws -> any SpeechEngine {
        try Task.checkCancellation()
        guard !closed else { throw ProviderCatalogError.closed }
        if let cached, cached.0 == selection { return cached.1 }
        let previous = cached
        cached = nil
        if let previous { await previous.1.shutdown() }
        try Task.checkCancellation()
        guard !closed else { throw ProviderCatalogError.closed }
        let engine = VolcSpeechEngine(appKey: selection.appKey, accessKey: selection.accessKey, resourceId: selection.resourceID, log: log)
        cached = (selection, engine)
        return engine
    }

    func close() async {
        closed = true
        if let cached { await cached.1.shutdown() }
        cached = nil
    }
}
