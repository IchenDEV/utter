import Foundation
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
final class ModelLifecycle: ModelLifecycleService {
    private let settings: any SettingsService
    private let credentials: any CredentialsService
    private let configuration: (any ConfigurationService)?
    private let access: any ModelResourceAccess
    private let files: any ModelFilesService
    private let processing: any ProcessingModelService
    private let speech: any ProviderCatalog<SpeechProviderRequest, any SpeechEngine>
    private let generation: any ProviderCatalog<GenerationPurpose, any TextGenerationService>
    private let scope: PluginScope
    private var closed = false
    private var active = 0
    private var speechReady = false
    private var textReady = false
    private var failure: String?
    private var observers: [UUID: (ModelLifecycleSnapshot) -> Void] = [:]
    var snapshot: ModelLifecycleSnapshot {
        ModelLifecycleSnapshot(loading: active > 0, speechReady: speechReady, textReady: textReady, error: failure)
    }

    init(settings: any SettingsService, credentials: any CredentialsService, configuration: (any ConfigurationService)?,
         access: any ModelResourceAccess, files: any ModelFilesService, processing: any ProcessingModelService,
         speech: any ProviderCatalog<SpeechProviderRequest, any SpeechEngine>,
         generation: any ProviderCatalog<GenerationPurpose, any TextGenerationService>, scope: PluginScope) {
        self.settings = settings; self.credentials = credentials; self.configuration = configuration
        self.access = access; self.files = files; self.processing = processing
        self.speech = speech; self.generation = generation; self.scope = scope
    }

    func observe(_ callback: @escaping (ModelLifecycleSnapshot) -> Void) -> UUID {
        let id = UUID()
        if !closed { observers[id] = callback }
        return id
    }
    func removeObserver(_ id: UUID) { observers[id] = nil }
    func revoke() { closed = true; observers.removeAll() }

    func preloadOnLaunch() async {
        if settings.values.preloadSpeechModelOnLaunch { try? await preloadSpeech() }
        if settings.values.preloadFormattingModelOnLaunch, !Task.isCancelled { try? await preloadText() }
    }

    func preloadSpeech() async throws {
        guard let frozen = try preflight({ try speechRequest() }) else { return }
        try await run {
            let engine = try await self.speech.create(id: frozen.0, request: frozen.1)
            await engine.prepare()
            try Task.checkCancellation()
            guard engine.isReady else { throw IntegrationError.modelNotReady }
            self.speechReady = true
        }
    }

    private func speechRequest() throws -> (String, SpeechProviderRequest)? {
        var values = credentials.snapshot.applying(to: settings.values)
        let bindings = try configuration?.sessionSnapshot.bindings ?? [:]
        let id = bindings["speech"] ?? values.speechEngine.rawValue
        guard let descriptor = speech.descriptors.first(where: { $0.id == id || $0.legacyIDs.contains(id) }) else {
            throw ProviderCatalogError.unknownIdentifier(id)
        }
        if descriptor.legacyIDs.contains(SpeechEngineType.apple.rawValue) || descriptor.legacyIDs.contains(SpeechEngineType.volc.rawValue) { return nil }
        if let type = descriptor.legacyIDs.compactMap(SpeechEngineType.init(rawValue:)).first { values.speechEngine = type }
        let selection = SpeechSelection(settings: values, providerID: descriptor.id)
        let frozen = FrozenModelFiles(modelID: selection.model, using: files)
        let url = frozen.installedSpeechModelURL(selection.model)
        if selection.type == .whisper {
            let url = frozen.installedWhisperURL(selection.model) ?? frozen.whisperVariantURL(selection.model)
            guard frozen.whisperModelIsComplete(at: url) else { throw IntegrationError.modelNotReady }
        } else if !descriptor.modelIDs.isEmpty, url == nil { throw IntegrationError.modelNotReady }
        let selected = SpeechSelection(providerID: descriptor.id, type: selection.type, model: selection.model,
            modelPath: url?.path ?? selection.modelPath, locale: selection.locale,
            appKey: selection.appKey, accessKey: selection.accessKey, resourceID: selection.resourceID)
        return (descriptor.id, SpeechProviderRequest(selection: selected, modelFiles: frozen))
    }

    func preloadText() async throws {
        guard let frozen = try preflight({ try textOptions() }) else { return }
        try await run {
            _ = try await self.processing.prepare(frozen)
            self.textReady = true
        }
    }

    private func textOptions() throws -> TextProcessingOptions? {
        let values = credentials.snapshot.applying(to: settings.values)
        var options = TextProcessingOptions(settings: values)
        let bindings = try configuration?.sessionSnapshot.bindings ?? [:]
        let id = bindings["text"] ?? (values.useRemoteLLM ? "generation.remote" : values.localLLMBackend == .espresso ? "generation.ane" : "generation.mlx")
        guard let descriptor = generation.descriptors.first(where: { $0.id == id || $0.legacyIDs.contains(id) }) else {
            throw ProviderCatalogError.unknownIdentifier(id)
        }
        guard descriptor.modelLocation != .remote else { return nil }
        options = options.selecting(descriptor).freezingModelLocations(using: files)
        options.fallbackProviderID = bindings["fallback"] ?? options.fallbackProviderID
        return options
    }

    private func preflight<Value>(_ operation: () throws -> Value) throws -> Value {
        guard !closed, scope.isActive else { throw CancellationError() }
        do { return try operation() }
        catch {
            failure = SessionFailurePresentation(error: error).message
            publish()
            throw error
        }
    }

    func unloadSpeech(providerID: String?) async throws {
        let ids = speech.descriptors.filter {
            guard let providerID else { return true }
            return $0.id == providerID || $0.legacyIDs.contains(providerID)
        }.map(\.id)
        try await run {
            for id in ids { try await self.speech.reset(id: id) }
            self.speechReady = false
        }
    }
    func unloadText() async throws {
        try await run { try await self.processing.unload(); self.textReady = false }
    }
    func benchmark(_ modelID: String) async throws -> ModelBenchmarkResult {
        try await run { try await self.processing.benchmark(modelID) }
    }
    func validateBundle(at url: URL) async throws {
        try await run {
            let provider = try await self.generation.create(id: "generation.ane", request: .inference)
            try await provider.validateModel(at: url)
        }
    }

    private func run<Value>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        guard !closed, scope.isActive else { throw CancellationError() }
        active += 1; failure = nil; publish()
        defer { active -= 1; publish() }
        do {
            return try await scope.run {
                try await self.access.withAccess { try await operation() }
            }
        } catch {
            if !(error is CancellationError) { failure = SessionFailurePresentation(error: error).message }
            throw error
        }
    }
    private func publish() { if !closed { for callback in Array(observers.values) { callback(snapshot) } } }
}
