import AVFoundation
import Foundation
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterModels
import UtterProcessing
import UtterRuntime
@testable import UtterSession

@MainActor
final class VoiceWorkflowFixture {
    let suite = "VoiceWorkflow-" + UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let engine = WorkflowSpeech()
    let capture = WorkflowCapture()
    let output = WorkflowOutput()
    let files = WorkflowFiles()
    let recipe = WorkflowRecipe()
    var speechRequests: [SpeechProviderRequest] = []
    private(set) var runtime: PluginRuntime!
    private var plugins: [PluginRegistration] = []

    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults.set(true, forKey: "developerInterfaceEnabled")
        defaults.set(false, forKey: "useScreenContext")
        files.url = directory.appendingPathComponent("old-model")
        try FileManager.default.createDirectory(at: files.url!, withIntermediateDirectories: true)
        let capabilities = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.voice-capabilities", provides: [
            ModelServices.files.reference, SpeechServices.providers.reference, GenerationServices.providers.reference,
            ModeServices.recipes.reference, AudioServices.capture.reference, AudioServices.files.reference,
            AudioServices.evidence.reference, MacServices.output.reference, MacServices.target.reference
        ])) { [self] context, _ in
            let speech = ProviderRegistry<SpeechProviderRequest, any SpeechEngine>()
            try speech.register(ProviderDefinition(descriptor: ProviderDescriptor(id: "speech.fixture", legacyIDs: ["apple"], displayName: "Fixture")) { [self] request in
                speechRequests.append(request)
                return engine
            }, scope: context.scope)
            let generation = ProviderRegistry<GenerationPurpose, any TextGenerationService>()
            try generation.register(ProviderDefinition(descriptor: ProviderDescriptor(id: "generation.mlx", displayName: "Fixture")) { _ in WorkflowGeneration() }, scope: context.scope)
            let modes = ProviderRegistry<Void, any ModeRecipeService>()
            for id in ["mode.direct", "mode.formatting", "mode.command", "mode.translation", "mode.edit"] {
                try modes.register(ProviderDefinition(descriptor: ProviderDescriptor(id: id, displayName: id)) { [recipe] _ in recipe }, scope: context.scope)
            }
            try context.provide(ModelServices.files, value: files)
            try context.provide(SpeechServices.providers, value: speech)
            try context.provide(GenerationServices.providers, value: generation)
            try context.provide(ModeServices.recipes, value: modes)
            try context.provide(AudioServices.capture, value: capture)
            try context.provide(AudioServices.files, value: WorkflowAudioFiles())
            try context.provide(AudioServices.evidence, value: WorkflowEvidence())
            try context.provide(MacServices.output, value: output)
            try context.provide(MacServices.target, value: WorkflowTargets())
        }
        plugins = [DataPlugins.settings(defaults: defaults), DataPlugins.credentials(), DataPlugins.notifications(),
                   DataPlugins.integrationClients(defaults: defaults), DataPlugins.dictionary(directoryURL: directory),
                   DataPlugins.lexicons(), DataPlugins.history(directoryURL: directory, reportError: { _ in }),
                   DataPlugins.diagnostics(WorkflowLog()), ModelPlugins.resourceAccess(), capabilities,
                   ProcessingPlugins.preparation(), SessionPlugins.voiceWorkflows(), SessionPlugins.execution(), SessionPlugins.api()]
        runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
    }
    func start() async throws { try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) }) }
    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

final class WorkflowSpeech: SpeechEngine {
    var isReady = true
    var preparing = false
    var holdPreparation = false
    var onPermission: (() -> Void)?
    var vocabulary: [String] = []
    var transcribed: [URL?] = []
    private var preparation: CheckedContinuation<Void, Never>?
    func requestPermission() async throws { onPermission?() }
    func prepare() async {
        preparing = true
        if holdPreparation { await withCheckedContinuation { preparation = $0 } }
    }
    func configureRecognition(context: SpeechRecognitionContext) { vocabulary = context.phrases }
    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        transcribed.append(audioURL)
        return "Hello world."
    }
    func release() { preparation?.resume(); preparation = nil }
}

@MainActor
final class WorkflowCapture: CaptureService {
    var requests: [CaptureRequest] = []
    let recording = WorkflowRecording()
    var error: Error?
    var callbacks: CaptureCallbacks?
    func begin(_ request: CaptureRequest, callbacks: CaptureCallbacks) async throws -> any OwnedRecording {
        requests.append(request)
        self.callbacks = callbacks
        if let error { throw error }
        return recording
    }
}

@MainActor
final class WorkflowRecording: OwnedRecording {
    var closed = false
    func finish() async throws -> CapturedAudio {
        var activity = AudioCaptureActivity()
        activity.record(rms: 0.1, frameCount: 1_600)
        return CapturedAudio(url: URL(fileURLWithPath: "/captured.wav"), activity: activity)
    }
    func close() async { closed = true }
}

@MainActor
final class WorkflowOutput: OutputService {
    var requests: [DeliveryRequest] = []
    let delivery = WorkflowDelivery()
    func prepare(_ request: DeliveryRequest, isSessionCurrent: @escaping () -> Bool) throws -> any PreparedDelivery {
        requests.append(request)
        guard isSessionCurrent() else { throw CancellationError() }
        return delivery
    }
}

@MainActor
final class WorkflowDelivery: PreparedDelivery {
    var receipt: DeliveryReceipt?
    var committing = false
    var closing = false
    var heldCommit = false
    var heldClose = false
    private var commitWaiter: CheckedContinuation<Void, Never>?
    private var closeWaiter: CheckedContinuation<Void, Never>?
    func commit() async -> DeliveryReceipt {
        committing = true
        if heldCommit { await withCheckedContinuation { commitWaiter = $0 } }
        let value = DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste)
        receipt = value
        return value
    }
    func close() async {
        closing = true
        if heldClose { await withCheckedContinuation { closeWaiter = $0 } }
    }
    func releaseCommit() { commitWaiter?.resume(); commitWaiter = nil }
    func releaseClose() { closeWaiter?.resume(); closeWaiter = nil }
}

@MainActor
final class WorkflowRecipe: ModeRecipeService {
    var requests: [ProcessingRequest] = []
    func process(_ request: ProcessingRequest) async throws -> ProcessingResult {
        requests.append(request)
        return ProcessingResult(text: request.text + " Formatted.")
    }
}

final class WorkflowGeneration: TextGenerationService, @unchecked Sendable {
    func generate(_ request: TextGenerationRequest) async throws -> String { "Unused" }
}

final class WorkflowFiles: ModelFilesService, @unchecked Sendable {
    var url: URL?
    func installedTextModelURL(_ id: String) -> URL? { url }
    func installedSpeechModelURL(_ id: String) -> URL? { url }
    func speechRequiredFiles(_ id: String) -> [String] { ["weights"] }
    func textModelIsComplete(at url: URL) -> Bool { true }
    func installedWhisperURL(_ id: String) -> URL? { url }
    func whisperVariantURL(_ id: String) -> URL { url ?? URL(fileURLWithPath: "/missing") }
    func whisperModelIsComplete(at url: URL) -> Bool { true }
}

@MainActor
private final class WorkflowAudioFiles: AudioFileService {
    func inspect(_ url: URL) throws -> AudioFileMetadata { AudioFileMetadata(url: url, frameCount: 1600, sampleRate: 16000, channels: 1) }
}
@MainActor
private final class WorkflowEvidence: SpeechEvidenceService {
    func containsSpeech(at url: URL?) async throws -> Bool { true }
}
@MainActor
private final class WorkflowTargets: TargetCaptureService {
    func capture(_ request: TargetCaptureRequest) throws -> any OutputTargetLease { WorkflowTarget() }
}
@MainActor
private final class WorkflowTarget: OutputTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 123
    let context = InputContext(appName: "Editor", bundleIdentifier: "fixture.editor", outputMode: .processed, inputLanguage: .english, source: .menuBar)
    let isValid = true
    let isCurrent = true
}
private struct WorkflowLog: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
