import UtterMediaContracts
import UtterPresentationContracts
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
import UtterContracts
import UtterModels

extension ModelDownloadRecovery {
    static func purgePartialArtifacts(kind: ModelDownloadKind, modelID: String) -> CleanupResult {
        purgePartialArtifacts(kind: kind, modelID: modelID, storageRoot: ModelStorage.huggingFaceBase)
    }
    static func partialArtifactURLs(kind: ModelDownloadKind, modelID: String) -> [URL] {
        partialArtifactURLs(kind: kind, modelID: modelID, storageRoot: ModelStorage.huggingFaceBase)
    }
    static func beginNewGeneration(kind: ModelDownloadKind, modelID: String) -> RelocationResult {
        beginNewGeneration(kind: kind, modelID: modelID, storageRoot: ModelStorage.huggingFaceBase)
    }
    static func relocateStaleGeneration(kind: ModelDownloadKind, modelID: String) -> RelocationResult {
        relocateStaleGeneration(kind: kind, modelID: modelID, storageRoot: ModelStorage.huggingFaceBase)
    }
    static func ensureLiveArtifactRoots(kind: ModelDownloadKind, modelID: String) {
        ensureLiveArtifactRoots(kind: kind, modelID: modelID, storageRoot: ModelStorage.huggingFaceBase)
    }
}
