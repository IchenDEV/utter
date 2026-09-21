import Foundation

enum ModelDownloadKind: Hashable {
    case whisper
    case llm
    case asr
}

struct ModelDownloadKey: Hashable {
    let kind: ModelDownloadKind
    let modelID: String
}

@MainActor
final class ModelDownloadTasks {
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var entries: [ModelDownloadKey: Entry] = [:]

    func run(
        key: ModelDownloadKey,
        operation: @escaping @MainActor (UUID) async -> Void
    ) async {
        if let existing = entries[key] {
            await existing.task.value
            return
        }

        let token = UUID()
        let task = Task { @MainActor in
            await operation(token)
        }
        entries[key] = Entry(token: token, task: task)
        await task.value

        if entries[key]?.token == token {
            entries.removeValue(forKey: key)
        }
    }

    /// True while `token` still owns `key`. A superseded run must check this
    /// before writing a terminal status, otherwise an abandoned transfer that
    /// only notices cancellation late could overwrite the state of its retry.
    func isCurrent(_ key: ModelDownloadKey, token: UUID) -> Bool {
        entries[key]?.token == token
    }

    func isActive(_ key: ModelDownloadKey) -> Bool {
        entries[key] != nil
    }

    /// Cancels the run and forgets it immediately. Dropping the entry lets a
    /// retry start even when the underlying transfer never observes cancellation.
    func cancel(_ key: ModelDownloadKey) {
        entries[key]?.task.cancel()
        entries.removeValue(forKey: key)
    }
}

@MainActor
extension ModelCatalog {
    func cancelDownload(_ id: String, kind: ModelDownloadKind) {
        let key = ModelDownloadKey(kind: kind, modelID: id)
        guard downloadTasks.isActive(key) else { return }
        downloadTasks.cancel(key)
        markDownloadPaused(id, kind: kind)
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
