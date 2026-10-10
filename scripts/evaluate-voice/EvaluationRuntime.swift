import Foundation
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterModels
import UtterMLX
import UtterWhisper
import UtterAudio
import UtterEvaluation
import UtterProcessing
import UtterRuntime

@MainActor
struct EvaluationRuntime {
    let runtime: PluginRuntime
    let backend: EvaluationBackend
    private let defaults: UserDefaults
    private let suiteName: String

    init(model: URL, modelID: String, speech: SpeechEvaluationSelection?) throws {
        suiteName = "UtterVoiceEval-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw CocoaError(.fileReadUnknown) }
        self.defaults = defaults
        let backend = EvaluationBackend()
        self.backend = backend
        let fixtures = PluginRegistration(descriptor: PluginDescriptor(id: "evaluation.inputs",
            provides: [ModelServices.files.reference, DataServices.dictionarySnapshot.reference])) { context, _ in
            try context.provide(ModelServices.files, value: EvaluationFiles(model: model, modelID: modelID, speech: speech))
            try context.provide(DataServices.dictionarySnapshot, value: EvaluationDictionary())
        }
        let provider = PluginRegistration(descriptor: PluginDescriptor(id: "evaluation.provider",
            requires: [GenerationServices.providers.required, GenerationServices.mlx.required])) { context, _ in
            let registry = try context.require(GenerationServices.providers)
            await backend.attach(try await registry.create(id: "generation.mlx", request: .inference))
            try registry.register(ProviderDefinition(descriptor: ProviderDescriptor(
                id: "evaluation.text", displayName: "Evaluation local model")) { _ in backend }, scope: context.scope)
        }
        var plugins = [DataPlugins.settings(defaults: defaults), DataPlugins.lexicons(),
            DataPlugins.diagnostics(EvaluationDiagnostics()), fixtures, ModelPlugins.resourceAccess(),
            ModelPlugins.textProviders(), MLXPlugins.text(), provider, ProcessingPlugins.text(),
            ModePlugins.recipes(), ModePlugins.direct(), ModePlugins.formatting(),
            ModePlugins.command(), ModePlugins.translation(), ProcessingPlugins.preparation(), AudioPlugins.files(), AudioPlugins.speechEvidence()]
        if let speech {
            plugins.append(ModelPlugins.speechProviders())
            switch speech.type {
            case .whisper: plugins.append(WhisperPlugins.speech())
            case .qwen3: plugins.append(MLXPlugins.qwenSpeech())
            case .firered: plugins.append(MLXPlugins.fireredSpeech())
            case .megaASR: plugins.append(MLXPlugins.megaSpeech())
            case .apple, .volc: throw VoiceEvaluationError.unavailableAudioProvider
            }
        }
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
    private var budget: EvaluationTokenBudget?
    func attach(_ model: any TextGenerationService) { self.model = model }
    func setCandidate(_ candidate: String?, budget: EvaluationTokenBudget) { suppliedCandidate = candidate; self.budget = budget }
    func generate(_ request: TextGenerationRequest) async throws -> String {
        try Task.checkCancellation()
        if let candidate = suppliedCandidate { suppliedCandidate = nil; return candidate }
        guard let model else { throw GenerationServiceError.modelUnavailable }
        guard let budget else { throw VoiceEvaluationError.tokenBudgetExceeded }
        let tokens = try await budget.reserve(request.maxTokens)
        return try await model.generate(TextGenerationRequest(prompt: request.prompt, systemPrompt: request.systemPrompt,
            modelID: request.modelID, modelURL: request.modelURL, maxTokens: tokens, temperature: request.temperature,
            remote: request.remote, frozenModel: request.frozenModel))
    }
    func unload() async { await model?.unload() }
}

private struct EvaluationFiles: ModelFilesService {
    let model: URL
    let modelID: String
    let speech: SpeechEvaluationSelection?
    func installedTextModelURL(_ id: String) -> URL? { id == modelID ? model : nil }
    func textModelIsComplete(at url: URL) -> Bool { ModelAssets.llmRepoIsComplete(at: url) }
    func installedSpeechModelURL(_ id: String) -> URL? { id == speech?.modelID ? speech?.model : nil }
    func speechRequiredFiles(_ id: String) -> [String] { MLXModelArtifacts.speech.first(where: { $0.id == id })?.requiredFiles ?? ["config.json", "model.safetensors", "tokenizer.json", "tokenizer_config.json"] }
    func installedWhisperURL(_ id: String) -> URL? { installedSpeechModelURL(id) }
    func whisperVariantURL(_ id: String) -> URL { installedSpeechModelURL(id) ?? model.appendingPathComponent("unavailable-speech") }
    func whisperModelIsComplete(at url: URL) -> Bool { ModelAssets.whisperModelIsComplete(at: url) }
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
