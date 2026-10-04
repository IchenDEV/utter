import Foundation
import UtterContracts
import UtterModels
import UtterMLX
import UtterPresentationContracts

@MainActor
extension ModelCatalog {
    static let shared = ModelCatalog()
    static var whisperDownloadBase: URL { ModelStorage.huggingFaceBase }
    static var asrDownloadBase: URL { whisperDownloadBase }

    convenience init(
        startupStorageRoot: URL = ModelStorage.huggingFaceBase,
        startupCleanup: StartupCleanupFactory = { ModelStorage.cleanupOrphanedGenerationStagingInBackground(storageRoot: $0) }
    ) {
        self.init(
            settings: .shared, log: UtterContracts.Log(service: Log.service), access: LocalModelAccessGate(),
            textDownloads: TextModelDownloadOperations(
                download: { id, staging, progress in
                    try await MLXModelDownloads.download(id, downloadBase: staging.downloadBase, cache: staging.hubCache, progress: progress)
                }, validate: { try await MLXModelDownloads.validate($0) }
            ), startupStorageRoot: startupStorageRoot, startupCleanup: startupCleanup
        )
        repairSelectedModels()
        start()
    }
}
