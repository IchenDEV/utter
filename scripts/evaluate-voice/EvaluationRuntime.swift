import Foundation
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterModels
import UtterMLX
import UtterProcessing
import UtterRuntime

@MainActor
struct EvaluationRuntime {
    let runtime: PluginRuntime
    let backend: EvaluationBackend
    private let defaults: UserDefaults
    private let suiteName: String

    init(model: URL, modelID: String) throws {
        suiteName = "UtterVoiceEval-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw CocoaError(.fileReadUnknown) }
        self.defaults = defaults
        let backend = EvaluationBackend()
        self.backend = backend
        let fixtures = PluginRegistration(descriptor: PluginDescriptor(id: "evaluation.inputs",
            provides: [ModelServices.files.reference, DataServices.dictionarySnapshot.reference])) { context, _ in
            try context.provide(ModelServices.files, value: EvaluationFiles(model: model, modelID: modelID))
            try context.provide(DataServices.dictionarySnapshot, value: EvaluationDictionary())
        }
        let provider = PluginRegistration(descriptor: PluginDescriptor(id: "evaluation.provider",
            requires: [GenerationServices.providers.required, GenerationServices.mlx.required])) { context, _ in
            let registry = try context.require(GenerationServices.providers)
            await backend.attach(try await registry.create(id: "generation.mlx", request: .inference))
            try registry.register(ProviderDefinition(descriptor: ProviderDescriptor(
                id: "evaluation.text", displayName: "Evaluation local model")) { _ in backend }, scope: context.scope)
        }
        let plugins = [DataPlugins.settings(defaults: defaults), DataPlugins.lexicons(),
            DataPlugins.diagnostics(EvaluationDiagnostics()), fixtures, ModelPlugins.resourceAccess(),
            ModelPlugins.textProviders(), MLXPlugins.text(), provider, ProcessingPlugins.text(),
            ModePlugins.recipes(), ModePlugins.direct(), ModePlugins.formatting(),
            ModePlugins.command(), ModePlugins.translation()]
        runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        selections = plugins.map { PluginSelection($0.descriptor.id) }
    }

    private let selections: [PluginSelection]
    func start() async throws { try await runtime.start(selections) }
    func close() async throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try await runtime.stop()
    }
}

actor EvaluationBackend: TextGenerationService {
    private var model: (any TextGenerationService)?
    private var suppliedCandidate: String?
    func attach(_ model: any TextGenerationService) { self.model = model }
    func setCandidate(_ candidate: String?) { suppliedCandidate = candidate }
    func generate(_ request: TextGenerationRequest) async throws -> String {
        try Task.checkCancellation()
        if let candidate = suppliedCandidate { suppliedCandidate = nil; return candidate }
        guard let model else { throw GenerationServiceError.modelUnavailable }
        return try await model.generate(request)
    }
    func unload() async { await model?.unload() }
}

private struct EvaluationFiles: ModelFilesService {
    let model: URL
    let modelID: String
    func installedTextModelURL(_ id: String) -> URL? { id == modelID ? model : nil }
    func textModelIsComplete(at url: URL) -> Bool { ModelAssets.llmRepoIsComplete(at: url) }
    func installedSpeechModelURL(_ id: String) -> URL? { nil }
    func speechRequiredFiles(_ id: String) -> [String] { [] }
    func installedWhisperURL(_ id: String) -> URL? { nil }
    func whisperVariantURL(_ id: String) -> URL { model.appendingPathComponent("unavailable-speech") }
    func whisperModelIsComplete(at url: URL) -> Bool { false }
}

private final class EvaluationDictionary: DictionarySnapshotService {
    func snapshot(industryLexicon: IndustryLexiconSnapshot, bundleIdentifier: String?, languageCode: String?) -> PersonalDictionarySnapshot {
        PersonalDictionarySnapshot(entries: [], editRules: [], industryLexicon: industryLexicon)
    }
}

private struct EvaluationDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
