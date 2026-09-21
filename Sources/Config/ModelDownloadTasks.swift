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
        var cancelled: Bool
    }

    private var entries: [ModelDownloadKey: Entry] = [:]

    /// Runs `operation` as the single writer for `key`.
    ///
    /// A duplicate request joins the in-flight run. A retry after `cancel` waits
    /// for the cancelled run to fully exit before starting, so the old transfer
    /// and its replacement never touch the same cache paths at the same time.
    func run(
        key: ModelDownloadKey,
        operation: @escaping @MainActor (UUID) async -> Void
    ) async {
        if let existing = entries[key] {
            let wasCancelled = existing.cancelled
            await existing.task.value
            guard wasCancelled else { return }
        }

        let token = UUID()
        let task = Task { @MainActor in
            await operation(token)
        }
        entries[key] = Entry(token: token, task: task, cancelled: false)
        await task.value

        if entries[key]?.token == token {
            entries.removeValue(forKey: key)
        }
    }

    /// True while `token` still owns `key` and has not been cancelled. A
    /// superseded or cancelled run must check this before writing a terminal
    /// status, so it cannot overwrite the state of the retry that replaced it.
    func isCurrent(_ key: ModelDownloadKey, token: UUID) -> Bool {
        guard let entry = entries[key] else { return false }
        return entry.token == token && !entry.cancelled
    }

    func isActive(_ key: ModelDownloadKey) -> Bool {
        entries[key] != nil
    }

    /// Requests cancellation without releasing the single-writer slot. A retry
    /// is serialized behind the cancelled run, so a transfer that ignores
    /// cancellation can only delay the retry, never race it on disk.
    func cancel(_ key: ModelDownloadKey) {
        guard var entry = entries[key] else { return }
        entry.cancelled = true
        entries[key] = entry
        entry.task.cancel()
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
