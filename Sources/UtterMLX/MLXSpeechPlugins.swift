import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension MLXPlugins {
    package static func qwenSpeech() -> PluginRegistration {
        speech(id: "speech.qwen", alias: .qwen3, title: L("engine.qwen3_short"), key: SpeechServices.qwen) { selection, files, access, log in
            QwenNativeASREngine(modelPath: selection.modelPath, modelID: selection.model, access: access, log: log)
        }
    }

    package static func fireredSpeech() -> PluginRegistration {
        speech(id: "speech.firered", alias: .firered, title: L("engine.firered_short"), key: SpeechServices.firered) { selection, files, access, log in
            MLXSTTEngine(modelID: selection.model, files: files, access: access, log: log)
        }
    }

    package static func megaSpeech() -> PluginRegistration {
        speech(id: "speech.mega", alias: .megaASR, title: L("engine.mega_short"), key: SpeechServices.mega) { selection, files, access, log in
            MLXSTTEngine(modelID: selection.model, files: files, access: access, log: log)
        }
    }

    private static func speech(
        id: String, alias: SpeechEngineType, title: String, key: ServiceKey<ProviderDescriptor>,
        make: @escaping (SpeechSelection, any ModelFilesService, any ModelResourceAccess, Log) -> any SpeechEngine
    ) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: id,
            requires: [SpeechServices.providers.required, ModelServices.files.required, ModelServices.resourceAccess.required, IntegrationServices.diagnostics.required],
            provides: [key.reference]
        )) { context, _ in
            let registry = try context.require(SpeechServices.providers)
            let files = try context.require(ModelServices.files)
            let access = try context.require(ModelServices.resourceAccess)
            let log = Log(service: try context.require(IntegrationServices.diagnostics))
            let cache = MLXSpeechCache { make($0, files, access, log) }
            try context.scope.onDispose { await cache.close() }
            let descriptor = ProviderDescriptor(id: id, legacyIDs: [alias.rawValue], displayName: title, recognitionVocabulary: alias == .qwen3 ? .personal : .all)
            try registry.register(ProviderDefinition(descriptor: descriptor) { request in try await cache.engine(request.selection) }, scope: context.scope)
            try context.provide(key, value: descriptor)
        }
    }
}

@MainActor
private final class MLXSpeechCache {
    private let make: (SpeechSelection) -> any SpeechEngine
    private var cached: (SpeechSelection, any SpeechEngine)?
    private var closed = false

    init(make: @escaping (SpeechSelection) -> any SpeechEngine) { self.make = make }

    func engine(_ selection: SpeechSelection) async throws -> any SpeechEngine {
        try Task.checkCancellation()
        guard !closed else { throw ProviderCatalogError.closed }
        if let cached, cached.0 == selection { return cached.1 }
        let previous = cached
        cached = nil
        if let previous { await previous.1.shutdown() }
        try Task.checkCancellation()
        guard !closed else { throw ProviderCatalogError.closed }
        let engine = make(selection)
        cached = (selection, engine)
        return engine
    }

    func close() async {
        closed = true
        if let cached { await cached.1.shutdown() }
        cached = nil
    }
}
