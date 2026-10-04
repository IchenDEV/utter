import UtterContracts
import Foundation

extension ModelCatalog {
    func asrRepoContainsRequiredFiles(_ id: String, at directory: URL?) -> Bool {
        ModelAssets.speechModelIsComplete(at: directory, requiredFiles: artifactsByID[id]?.requiredFiles ?? [])
    }
}
