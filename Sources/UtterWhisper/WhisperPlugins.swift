import Foundation
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
package enum WhisperPlugins {
    package static func speech() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "speech.whisper",
            requires: [SpeechServices.providers.required, ModelServices.files.required, ModelServices.resourceAccess.required, IntegrationServices.diagnostics.required],
            provides: [SpeechServices.whisper.reference]
        )) { context, _ in
            let registry = try context.require(SpeechServices.providers)
            let cache = WhisperProviderCache(
                files: try context.require(ModelServices.files), access: try context.require(ModelServices.resourceAccess),
                log: Log(service: try context.require(IntegrationServices.diagnostics))
            )
            try context.scope.onDispose { await cache.close() }
            let descriptor = ProviderDescriptor(id: "speech.whisper", legacyIDs: [SpeechEngineType.whisper.rawValue], displayName: L("engine.whisper_short"))
            try registry.register(ProviderDefinition(descriptor: descriptor) { request in try await cache.engine(request) }, scope: context.scope)
            try context.provide(SpeechServices.whisper, value: descriptor)
        }
    }
}

@MainActor
private final class WhisperProviderCache {
    private let files: any ModelFilesService
    private let access: any ModelResourceAccess
    private let log: Log
    private var cached: (String, WhisperEngine)?
    private var pending: (id: UUID, model: String, task: Task<WhisperEngine, Error>)?
    private var closed = false

    init(files: any ModelFilesService, access: any ModelResourceAccess, log: Log) {
        self.files = files
        self.access = access
        self.log = log
    }

    func engine(_ request: SpeechProviderRequest) async throws -> any SpeechEngine {
        try Task.checkCancellation()
        guard !closed else { throw ProviderCatalogError.closed }
        let identity = request.selection.model + ":" + (request.modelFiles?.revision ?? "live")
        if let pending {
            let loaded = try await pending.task.value
            try Task.checkCancellation()
            guard !closed else { throw ProviderCatalogError.closed }
            if pending.model == identity { return loaded }
        }
        if let cached, cached.0 == identity { return cached.1 }
        let previous = cached
        cached = nil
        if let previous { await previous.1.shutdown() }
        try Task.checkCancellation()
        guard !closed else { throw ProviderCatalogError.closed }
        let engine = WhisperEngine(modelName: request.selection.model, files: request.modelFiles.map { $0 as any ModelFilesService } ?? files, access: access, log: log)
        let task = Task {
            do {
                try await engine.loadModel(progress: request.progress)
                return engine
            } catch {
                await engine.shutdown()
                throw error
            }
        }
        let id = UUID()
        pending = (id, identity, task)
        defer { if pending?.id == id { pending = nil } }
        do {
            let loaded = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard !closed else { throw ProviderCatalogError.closed }
            cached = (identity, loaded)
            return loaded
        } catch {
            await engine.shutdown()
            throw error
        }
    }

    func close() async {
        closed = true
        pending?.task.cancel()
        if let pending, case .success(let engine) = await pending.task.result { await engine.shutdown() }
        if let cached { await cached.1.shutdown() }
        cached = nil
    }
}
