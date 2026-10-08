import Foundation
import UtterContracts

@MainActor
extension ModelCatalog {
    package func prepareCacheForRetry(
        kind: ModelDownloadKind,
        modelID: String,
        status: ModelStatus
    ) {
        if status.isError {
            let purged = ModelDownloadRecovery.purgePartialArtifacts(kind: kind, modelID: modelID, storageRoot: storage.root)
            if !purged.isEmpty {
                log.info(
                    "[ModelCatalog] Cleared \(purged.removedFiles) stale download file(s) for \(modelID)"
                )
            }
        }
        ModelDownloadRecovery.ensureLiveArtifactRoots(kind: kind, modelID: modelID, storageRoot: storage.root)
    }

    package func makeStallWatchdog(
        key: ModelDownloadKey,
        token: UUID,
        kind: ModelDownloadKind,
        modelID: String
    ) -> DownloadStallWatchdog {
        let watchdog = DownloadStallWatchdog()
        watchdogs.append(watchdog)
        watchdog.start { [weak self] in
            guard let self, self.downloadTasks.isCurrent(key, token: token) else { return }
            if self.cancelStalledDownload(modelID, kind: kind) {
                self.markStalled(kind: kind, modelID: modelID)
            }
        }
        return watchdog
    }

    package func markStalled(kind: ModelDownloadKind, modelID: String) {
        switch kind {
        case .whisper:
            guard let i = whisperModels.firstIndex(where: { $0.id == modelID }) else { return }
            whisperModels[i].status = .error(L("model.download_failed_stalled"))
            whisperModels[i].downloadProgress = 0
            whisperModels[i].downloadDetail = ""
            whisperModels[i].cacheSize = whisperVariantSize(modelID)
        case .llm:
            guard let i = llmModels.firstIndex(where: { $0.id == modelID }) else { return }
            llmModels[i].status = .error(L("model.download_failed_stalled"))
            llmModels[i].downloadProgress = 0
            llmModels[i].downloadDetail = ""
            llmModels[i].cacheSize = llmRepoSize(modelID)
        case .asr:
            guard let i = asrModels.firstIndex(where: { $0.id == modelID }) else { return }
            asrModels[i].status = .error(L("model.download_failed_stalled"))
            asrModels[i].downloadProgress = 0
            asrModels[i].downloadDetail = ""
            asrModels[i].cacheSize = asrRepoSize(modelID)
        }
    }
}
