import Foundation

extension ModelCatalog {
    func asrRepoSize(_ id: String, downloadBase: URL) -> Int64 {
        asrRequiredRepoIDs(for: id).reduce(0) { total, repositoryID in
            total + ModelStorage.directorySize(
                at: ModelStorage.asrRepoDir(repositoryID, downloadBase: downloadBase)
            )
        }
    }

    func asrMissingStatus(size: Int64) -> ModelStatus {
        size > 0 ? .error(L("model.asr_incomplete")) : .notDownloaded
    }

    func asrRepoSize(_ id: String) -> Int64 {
        asrRequiredRepoIDs(for: id).reduce(0) { total, repositoryID in
            guard let directory = ModelStorage.asrRepoDir(repositoryID) else { return total }
            return total + ModelStorage.directorySize(at: directory)
        }
    }
}
