import UtterPresentationContracts
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
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
    let target = WorkflowTarget()
    let screen = WorkflowScreen()
    let evidence = WorkflowEvidence()
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
            AudioServices.evidence.reference, MacServices.output.reference, MacServices.target.reference, MacServices.screen.reference
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
            try context.provide(AudioServices.evidence, value: evidence)
            try context.provide(MacServices.output, value: output)
            try context.provide(MacServices.target, value: WorkflowTargets(target: target))
            try context.provide(MacServices.screen, value: screen)
        }
        plugins = [DataPlugins.settings(defaults: defaults), DataPlugins.credentials(), DataPlugins.notifications(),
                   DataPlugins.integrationClients(defaults: defaults), DataPlugins.dictionary(directoryURL: directory),
                   DataPlugins.lexicons(), DataPlugins.history(directoryURL: directory, reportError: { _ in }), DataPlugins.memory(),
                   DataPlugins.diagnostics(WorkflowLog()), ModelPlugins.resourceAccess(), capabilities,
                   ProcessingPlugins.preparation(), SessionPlugins.outputs(), SessionPlugins.voiceWorkflows(), SessionPlugins.execution(), SessionPlugins.api()]
        runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
    }
    func start() async throws { try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) }) }
    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
final class WorkflowScreen: ScreenCaptureService {
    var requests: [ScreenContextMode] = []
    var snapshot = ScreenContextSnapshot.empty
    func capture(mode: ScreenContextMode) async throws -> ScreenContextSnapshot {
        requests.append(mode)
        return snapshot
    }
    func checkPermission() async throws -> Bool { snapshot.status != .permissionDenied }
    func requestPermission() {}
    func excludeWindow(_ id: UInt32) {}
    func includeWindow(_ id: UInt32) {}
}

final class WorkflowSpeech: SpeechEngine {
    var draining = false
    var holdDrain = false
    private var drainWaiter: CheckedContinuation<Void, Never>?
    var isReady = true
    var transcript = "Hello world."
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
        return transcript
    }
    func release() { preparation?.resume(); preparation = nil }
    func drainRecognition() async {
        draining = true
        if holdDrain { await withCheckedContinuation { drainWaiter = $0 } }
    }
    func releaseDrain() { drainWaiter?.resume(); drainWaiter = nil }
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
    var finished = false
    var stopped = false
    var rms: Float = 0.1
    var revoked = false
    func revoke() { revoked = true }
    func stopCapture() async { revoke(); stopped = true }
    func finish() async throws -> CapturedAudio {
        finished = true
        var activity = AudioCaptureActivity()
        activity.record(rms: rms, frameCount: 1_600)
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
    var anchor: (any OutputAnchor)?
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
        let value = DeliveryReceipt(operationID: UUID(), disposition: .accepted, effect: .paste, anchor: anchor, confirmation: .targetValue)
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
    var resolution: SpokenEditCommandLLMResolution?
    var resolutionContexts: [SpokenEditCommandResolutionContext] = []
    var holdFormatting = false
    var confirmsTranslation = true
    var translationProofTarget: TranslationLanguage?
    var formatting = false
    private var formattingWaiter: CheckedContinuation<Void, Never>?
    func resolveEditCommand(_ request: ProcessingRequest, context: SpokenEditCommandResolutionContext) async throws -> SpokenEditCommandLLMResolution? {
        resolutionContexts.append(context)
        return resolution
    }
    func process(_ request: ProcessingRequest) async throws -> ProcessingResult {
        requests.append(request)
        if request.mode == .direct { return ProcessingResult(text: request.text) }
        if request.mode == .formatting {
            formatting = true
            if holdFormatting { await withCheckedContinuation { formattingWaiter = $0 } }
        }
        if case .translation(let target) = request.mode, confirmsTranslation {
            let language = translationProofTarget ?? target
            let assessment = TranslationAssessment.assess(target: language,
                hasLinguisticContent: true, scores: [language.rawValue: 1])
            return ProcessingResult(text: request.text + " Formatted.",
                decision: ProcessingDecision(.accepted, translation: assessment))
        }
        return ProcessingResult(text: request.text + " Formatted.")
    }
    func releaseFormatting() { formattingWaiter?.resume(); formattingWaiter = nil }
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
final class WorkflowEvidence: SpeechEvidenceService {
    var hasSpeech = true
    func containsSpeech(at url: URL?) async throws -> Bool { hasSpeech }
}
@MainActor
private final class WorkflowTargets: TargetCaptureService {
    let target: WorkflowTarget
    init(target: WorkflowTarget) { self.target = target }
    func capture(_ request: TargetCaptureRequest) throws -> any OutputTargetLease { target }
}
@MainActor
final class WorkflowTarget: OutputTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 123
    let context = InputContext(appName: "Editor", bundleIdentifier: "fixture.editor", outputMode: .processed, inputLanguage: .english, source: .menuBar)
    var selectedText: String?
    var isValid = true
    var isCurrent = true
}
private struct WorkflowLog: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
