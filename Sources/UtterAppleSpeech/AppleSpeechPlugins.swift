import Foundation
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
package enum AppleSpeechPlugins {
    package static func speech() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "speech.apple",
            requires: [SpeechServices.providers.required, IntegrationServices.diagnostics.required],
            provides: [SpeechServices.apple.reference]
        )) { context, _ in
            let providers = try context.require(SpeechServices.providers)
            let log = Log(service: try context.require(IntegrationServices.diagnostics))
            let cache = AppleProviderCache(log: log)
            try context.scope.onDispose { cache.close() }
            let descriptor = ProviderDescriptor(id: "speech.apple", legacyIDs: [SpeechEngineType.apple.rawValue], displayName: L("engine.apple_speech"))
            try providers.register(ProviderDefinition(descriptor: descriptor) { request in
                try cache.engine(locale: request.selection.locale)
            }, scope: context.scope)
            try context.provide(SpeechServices.apple, value: descriptor)
        }
    }
}

@MainActor
private final class AppleProviderCache {
    private let log: Log
    private var engines: [String: AppleSpeechEngine] = [:]
    private var closed = false

    init(log: Log) { self.log = log }

    func engine(locale: String) throws -> any SpeechEngine {
        guard !closed else { throw ProviderCatalogError.closed }
        if let engine = engines[locale] { return engine }
        let engine = AppleSpeechEngine(locale: Locale(identifier: locale), log: log)
        engines[locale] = engine
        return engine
    }

    func close() {
        closed = true
        for engine in engines.values { engine.cancelListening() }
        engines.removeAll()
    }
}
