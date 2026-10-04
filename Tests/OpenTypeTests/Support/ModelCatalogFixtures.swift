import UtterMediaContracts
import UtterData
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import UtterContracts
import UtterModels
import UtterMLX
import UtterPresentationContracts

@MainActor
extension ModelCatalog {
    static let shared = ModelCatalog()
    static var defaultLLMModels: [(String, String, String, ModelFamily?, ModelTier)] {
        MLXModelArtifacts.text.map { ($0.id, $0.displayName, $0.hint, $0.family, $0.tier) }
    }
    static var defaultASRModels: [(id: String, displayName: String, hint: String)] {
        MLXModelArtifacts.speech.map { ($0.id, $0.displayName, $0.hint) }
    }
    static let mlxSTTModelIDs = Set((MLXModelArtifacts.firered + MLXModelArtifacts.mega).map(\.id))
    nonisolated static func asrRequiredFiles(for id: String) -> [String] {
        MLXModelArtifacts.speech.first(where: { $0.id == id })?.requiredFiles ?? ["config.json"]
    }
    nonisolated static func asrRepoContainsRequiredFiles(_ id: String, at directory: URL?) -> Bool {
        ModelAssets.speechModelIsComplete(at: directory, requiredFiles: asrRequiredFiles(for: id))
    }
    static var whisperDownloadBase: URL { ModelStorage.huggingFaceBase }
    static var asrDownloadBase: URL { whisperDownloadBase }

    convenience init(
        startupStorageRoot: URL = ModelStorage.huggingFaceBase,
        startupCleanup: @escaping StartupCleanupFactory = { ModelStorage.cleanupOrphanedGenerationStagingInBackground(storageRoot: $0) }
    ) {
        self.init(
            settings: .shared, log: UtterContracts.Log(service: TestDiagnostics.service), access: LocalModelAccessGate(),
            textDownloads: TextModelDownloadOperations(
                download: { id, staging, progress in
                    try await MLXModelDownloads.download(id, downloadBase: staging.downloadBase, cache: staging.hubCache, progress: progress)
                }, validate: { try await MLXModelDownloads.validate($0) }
            ), artifacts: MLXModelArtifacts.text + MLXModelArtifacts.speech,
            speechDescriptors: { MLXModelArtifacts.speechDescriptors }, startupStorageRoot: startupStorageRoot, startupCleanup: startupCleanup
        )
        repairSelectedModels()
        start()
    }
}
