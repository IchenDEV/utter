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

/// Serializes every operation that touches a model's cache: downloads, partial
/// cleanup, and delete.
///
/// The awkward case is a retry after cancel when the underlying transfer ignores
/// cancellation and never returns. Waiting forever would mean the user can never
/// retry, so a cancelled writer is *abandoned* rather than patiently awaited: the
/// caller first moves the previous generation's cache aside (see
/// `ModelDownloadRecovery.relocateStaleGeneration`), then calls `abandon` to
/// release the slot. The abandoned writer can only touch the quarantined copy,
/// so a replacement may start safely. Deletion and cleanup still wait behind
/// every retired generation for that key.
@MainActor
final class ModelDownloadTasks {
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
    }

    private struct RetiredEntry {
        let token: UUID
        let task: Task<Void, Never>
        let onCompletion: @MainActor () -> Void
    }

    private var entries: [ModelDownloadKey: Entry] = [:]
    private var retiredEntries: [ModelDownloadKey: [RetiredEntry]] = [:]
    private var pendingCleanups: [ModelDownloadKey: [@MainActor () -> Void]] = [:]

    /// Runs `operation` as the single writer for `key`.
    ///
    /// - Duplicate request while a live run is active: joins it, does not restart.
    /// - Request after `abandon`: starts, because the abandoned writer was
    ///   already moved off the live cache. The retired writer stays tracked so
    ///   deletion can wait for its I/O and clean its quarantine afterwards.
    func run(
        key: ModelDownloadKey,
        operation: @escaping @MainActor (UUID) async -> Void
    ) async {
        if let existing = entries[key] {
            await existing.task.value
            return
        }

        await start(key: key, operation: operation)
    }

    /// True while `token` still owns `key`. A superseded or cancelled run must
    /// check this before writing a terminal status, so it cannot overwrite the
    /// state of the retry that replaced it.
    func isCurrent(_ key: ModelDownloadKey, token: UUID) -> Bool {
        entries[key]?.token == token
    }

    func isActive(_ key: ModelDownloadKey) -> Bool {
        entries[key] != nil
    }

    /// Requests cancellation without releasing the slot. The caller then moves
    /// the stale cache aside and calls `abandon` so a retry may start.
    func cancel(_ key: ModelDownloadKey) {
        entries[key]?.task.cancel()
    }

    /// Releases the live slot for a cancelled run whose caller has already
    /// isolated the previous generation's cache. The abandoned task remains
    /// tracked until it returns, so delete cannot race its final file I/O.
    @discardableResult
    func abandon(
        _ key: ModelDownloadKey,
        onCompletion: @escaping @MainActor () -> Void = {}
    ) -> Bool {
        guard let entry = entries.removeValue(forKey: key) else { return false }
        entry.task.cancel()
        retiredEntries[key, default: []].append(
            RetiredEntry(token: entry.token, task: entry.task, onCompletion: onCompletion)
        )
        return true
    }

    /// Runs `operation` once every current or retired writer for `key` has
    /// returned. This keeps deletion and partial cleanup out of the way of a
    /// cancelled transfer that is still winding down.
    func runExclusive(
        key: ModelDownloadKey,
        operation: @escaping @MainActor (UUID) async -> Void
    ) async {
        while let task = nextTask(for: key) {
            await task.value
        }
        await start(key: key, operation: operation)
    }

    private func nextTask(for key: ModelDownloadKey) -> Task<Void, Never>? {
        if let entry = entries[key] { return entry.task }
        return retiredEntries[key]?.first?.task
    }

    /// Creates and awaits the single current writer. The task removes its own
    /// generation before becoming complete, so a late retired writer cannot
    /// clear a replacement entry.
    private func start(
        key: ModelDownloadKey,
        operation: @escaping @MainActor (UUID) async -> Void
    ) async {
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.finish(key: key, token: token) }
            await operation(token)
        }
        entries[key] = Entry(token: token, task: task)
        await task.value
    }

    private func finish(key: ModelDownloadKey, token: UUID) {
        if entries[key]?.token == token {
            entries.removeValue(forKey: key)
            drainCleanupsIfIdle(for: key)
            return
        }

        guard var retired = retiredEntries[key],
              let index = retired.firstIndex(where: { $0.token == token }) else { return }
        let entry = retired.remove(at: index)
        if retired.isEmpty {
            retiredEntries.removeValue(forKey: key)
        } else {
            retiredEntries[key] = retired
        }
        pendingCleanups[key, default: []].append(entry.onCompletion)
        drainCleanupsIfIdle(for: key)
    }

    /// A cancelled generation's quarantine may be merged back into the live
    /// cache only after every generation for this key has stopped writing. This
    /// prevents a completed old file from being restored while a replacement is
    /// still downloading the same path.
    private func drainCleanupsIfIdle(for key: ModelDownloadKey) {
        guard entries[key] == nil, retiredEntries[key] == nil,
              let cleanups = pendingCleanups.removeValue(forKey: key) else { return }
        for cleanup in cleanups {
            cleanup()
        }
    }
}

@MainActor
extension ModelCatalog {
    /// Cancels a running download, isolates the previous generation's cache so
    /// the abandoned writer cannot corrupt a retry, then releases the slot so
    /// the user can immediately resume.
    func cancelDownload(_ id: String, kind: ModelDownloadKind) {
        guard stopDownload(id, kind: kind) else { return }
        markDownloadPaused(id, kind: kind)
    }

    /// Cancels and isolates a transfer whose progress watchdog has expired.
    /// Unlike an ordinary cancellation, the caller supplies the stalled error
    /// after the old generation has been removed from the live slot.
    @discardableResult
    func abandonStalledDownload(_ id: String, kind: ModelDownloadKind) -> Bool {
        stopDownload(id, kind: kind)
    }

    @discardableResult
    private func stopDownload(_ id: String, kind: ModelDownloadKind) -> Bool {
        let key = ModelDownloadKey(kind: kind, modelID: id)
        guard downloadTasks.isActive(key) else { return false }
        downloadTasks.cancel(key)
        let relocation = ModelDownloadRecovery.relocateStaleGeneration(kind: kind, modelID: id)
        let abandoned = downloadTasks.abandon(key) {
            ModelDownloadRecovery.clearQuarantine(relocation)
        }
        if !abandoned {
            ModelDownloadRecovery.clearQuarantine(relocation)
        }
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
