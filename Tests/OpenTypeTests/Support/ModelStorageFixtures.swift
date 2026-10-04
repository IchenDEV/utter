import UtterContracts
import UtterMediaContracts
import UtterData
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import UtterModels
import UtterPresentationContracts

extension ModelStorage {
    static var root: URL { ConfiguredModelFiles.storageRoot(settings: AppSettings.shared.snapshot) }
    static var huggingFaceBase: URL {
        root
    }
    static func generationStaging(for token: UUID) -> ModelDownloadStaging {
        generationStaging(for: token, storageRoot: huggingFaceBase)
    }
    static func cleanupOrphanedGenerationStaging() -> Int {
        cleanupOrphanedGenerationStaging(storageRoot: huggingFaceBase)
    }
    static func cleanupOrphanedGenerationStagingInBackground() -> Task<Int, Never> {
        cleanupOrphanedGenerationStagingInBackground(storageRoot: huggingFaceBase)
    }
    static var hubModelsBase: URL {
        huggingFaceBase.appendingPathComponent("models")
    }
    static func whisperVariantDir(_ variant: String) -> URL {
        whisperVariantDir(variant, downloadBase: huggingFaceBase)
    }
    static var whisperRepoCacheRoot: URL {
        hubModelsBase.appendingPathComponent("argmaxinc/whisperkit-coreml")
    }
    static func hubModelRepoDir(_ modelID: String) -> URL {
        hubModelRepoDir(modelID, downloadBase: huggingFaceBase)
    }
    static func llmRepoDir(_ modelID: String) -> URL? {
        if let local = localLLMURL(modelID) { return local }
        let dir = hubModelRepoDir(modelID)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }
    static func installedLLMURL(_ modelID: String) -> URL? {
        guard let dir = llmRepoDir(modelID), llmRepoIsComplete(at: dir) else { return nil }
        return dir
    }
    static func asrRepoDir(_ modelID: String) -> URL? {
        let dir = hubModelRepoDir(modelID)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }
    static func localWhisperURL(_ id: String) -> URL? {
        guard let path = AppSettings.shared.localWhisperModelPaths[id] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
    static func localLLMURL(_ id: String) -> URL? {
        guard let path = AppSettings.shared.localLLMModelPaths[id] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
}
