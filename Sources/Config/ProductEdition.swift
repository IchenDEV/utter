import Foundation

struct ProductCapabilities: Equatable, Sendable {
    let modelManagement: Bool
    let modelDownloads: Bool
    let remoteInference: Bool
    let developerIntegrations: Bool
    let customPrompts: Bool
    let externalLinks: Bool
    let translation: Bool
    let voiceCommands: Bool
    let requiresInsertionReview: Bool
    let contextMemory: Bool
    let correctionLearning: Bool
    let dictionaryTransfer: Bool
    let activityHistory: Bool
}

struct BundledModelSpecification: Equatable, Sendable {
    let id: String
    let displayName: String
    let relativePath: String
}

struct ProductEditionProfile: Equatable, Sendable {
    let id: String
    let industry: String
    let minimumMemoryGB: Int
    let maximumFormattingCharacters: Int
    let maximumGenerationTokens: Int
    let speechModel: BundledModelSpecification
    let speechRuntime: BundledModelSpecification
    let formattingModel: BundledModelSpecification
    let capabilities: ProductCapabilities

    static let medicalOffline = ProductEditionProfile(
        id: "medical-offline-cn-v1",
        industry: "medical",
        minimumMemoryGB: 8,
        maximumFormattingCharacters: 2_048,
        maximumGenerationTokens: 2_048,
        speechModel: BundledModelSpecification(
            id: "mlx-community/Qwen3-ASR-0.6B-bf16",
            displayName: "Qwen3-ASR 0.6B BF16",
            relativePath: "speech"
        ),
        speechRuntime: BundledModelSpecification(
            id: LocalASRRuntime.qwenRequirement,
            displayName: "Qwen3-ASR MLX Runtime",
            relativePath: "speech-runtime"
        ),
        formattingModel: BundledModelSpecification(
            id: "mlx-community/Qwen3-0.6B-4bit",
            displayName: "Qwen3 0.6B 4-bit",
            relativePath: "formatting"
        ),
        capabilities: ProductCapabilities(
            modelManagement: false,
            modelDownloads: false,
            remoteInference: false,
            developerIntegrations: false,
            customPrompts: false,
            externalLinks: false,
            translation: true,
            voiceCommands: false,
            requiresInsertionReview: true,
            contextMemory: false,
            correctionLearning: false,
            dictionaryTransfer: false,
            activityHistory: false
        )
    )
}

enum ProductEdition {
    static let current = ProductEditionProfile.medicalOffline

    static var localizedName: String { L("edition.medical_offline.name") }

    @MainActor
    static func apply(to settings: AppSettings, resourceURL: URL? = Bundle.main.resourceURL) {
        settings.speechEngine = .qwen3
        settings.qwenASRModel = current.speechModel.id
        settings.llmModel = current.formattingModel.id
        settings.outputMode = .processed
        settings.enableInstantInsert = false
        settings.languageStyle = .professional
        settings.customStylePrompt = ""
        settings.useCustomSystemPrompt = false
        settings.customSystemPrompt = ""
        settings.useRemoteLLM = false
        settings.remoteAPIKey = ""
        settings.remoteBaseURL = ""
        settings.remoteModel = ""
        settings.developerInterfaceEnabled = false
        settings.enableMemory = false
        settings.enableCorrectionLearning = false
        settings.localASRPythonPath = ""
        settings.localWhisperModelPaths = [:]
        settings.localASRModelPaths = [:]
        settings.localLLMModelPaths = [:]

        guard let paths = OfflineModelBundle.configuredPaths(resourceURL: resourceURL) else { return }
        settings.localASRModelPaths = [current.speechModel.id: paths.speech.path]
        settings.localASRPythonPath = paths.speechRuntime
            .appendingPathComponent("bin/python")
            .path
        settings.localLLMModelPaths = [current.formattingModel.id: paths.formatting.path]
    }
}
