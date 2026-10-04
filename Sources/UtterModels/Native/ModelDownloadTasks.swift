import UtterContracts
import Foundation

@MainActor
extension ModelCatalog {
    /// Cancels a running download and marks it resumable. Its generation root
    /// remains owned by the still-running operation; a later Resume gets a
    /// fresh root immediately.
    package func cancelDownload(_ id: String, kind: ModelDownloadKind) {
        guard stopDownload(id, kind: kind) else { return }
        markDownloadPaused(id, kind: kind)
    }

    /// Cancels a transfer whose progress watchdog has expired.
    @discardableResult
    package func cancelStalledDownload(_ id: String, kind: ModelDownloadKind) -> Bool {
        stopDownload(id, kind: kind)
    }

    @discardableResult
    private func stopDownload(_ id: String, kind: ModelDownloadKind) -> Bool {
        let key = ModelDownloadKey(kind: kind, modelID: id)
        guard downloadTasks.isActive(key) else { return false }
        downloadTasks.cancel(key)
        return true
    }

    private func markDownloadPaused(_ id: String, kind: ModelDownloadKind) {
        switch kind {
        case .whisper:
            guard let i = whisperModels.firstIndex(where: { $0.id == id }) else { return }
            whisperModels[i].status = .error(L("model.download_paused"))
            whisperModels[i].downloadProgress = 0
            whisperModels[i].downloadDetail = ""
            whisperModels[i].cacheSize = whisperVariantSize(id)
        case .llm:
            guard let i = llmModels.firstIndex(where: { $0.id == id }) else { return }
            llmModels[i].status = .error(L("model.download_paused"))
            llmModels[i].downloadProgress = 0
            llmModels[i].downloadDetail = ""
            llmModels[i].cacheSize = llmRepoSize(id)
        case .asr:
            guard let i = asrModels.firstIndex(where: { $0.id == id }) else { return }
            asrModels[i].status = .error(L("model.download_paused"))
            asrModels[i].downloadProgress = 0
            asrModels[i].downloadDetail = ""
            asrModels[i].cacheSize = asrRepoSize(id)
        }
    }
}
