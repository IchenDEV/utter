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
/// A cancelled writer keeps the slot until its underlying operation returns.
/// This is deliberate: the pinned Hub clients retain absolute `.incomplete`
/// URLs across network awaits, so moving a directory cannot prevent a late
/// continuation from reopening the original live path. A replacement is only
/// admitted after the old task has drained, which preserves one writer for the
/// dependency's actual path access behavior.
@MainActor
final class ModelDownloadTasks {
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
        var cancelRequested: Bool
    }

    private var entries: [ModelDownloadKey: Entry] = [:]
    /// A waiter that arrived while a cancelled operation was draining claims
    /// this token and starts the replacement once the old task has returned.
    /// Keeping the marker separate from `entries` also lets a later Resume
    /// start normally if no waiter was present during the drain.
    private var restartAfterCancellation: [ModelDownloadKey: UUID] = [:]

    /// Runs `operation` as the single writer for `key`.
    ///
    /// - Duplicate request while a live run is active: joins it, does not restart.
    /// - Request while a cancelled run is draining: waits for that run, then
    ///   claims the single replacement slot.
    func run(
        key: ModelDownloadKey,
        operation: @escaping @MainActor (UUID) async -> Void
    ) async {
        if let existing = entries[key] {
            let observedToken = existing.token
            await existing.task.value
            // Another waiter may have claimed the cancelled generation and
            // already started the replacement while this waiter was waking.
            // Join that replacement instead of starting a second writer.
            if let replacement = entries[key], replacement.token != observedToken {
                await replacement.task.value
                return
            }
            if restartAfterCancellation[key] == observedToken {
                restartAfterCancellation.removeValue(forKey: key)
                await start(key: key, operation: operation)
            }
            return
        }

        // A cancelled run that completed before this request has left a
        // restart marker, but this request itself is the new owner.
        restartAfterCancellation.removeValue(forKey: key)
        await start(key: key, operation: operation)
    }

    /// True while `token` still owns `key` and has not been cancelled. A
    /// cancelled writer remains the owner for disk serialization, but must stop
    /// publishing progress or terminal state to the UI.
    func isCurrent(_ key: ModelDownloadKey, token: UUID) -> Bool {
        guard let entry = entries[key] else { return false }
        return entry.token == token && !entry.cancelRequested
    }

    func isActive(_ key: ModelDownloadKey) -> Bool {
        entries[key] != nil
    }

    /// Requests cancellation without releasing the slot. The operation may
    /// retain absolute paths and continue file I/O after cancellation, so the
    /// slot is released only by `finish` after the operation actually returns.
    func cancel(_ key: ModelDownloadKey) {
        guard var entry = entries[key] else { return }
        entry.cancelRequested = true
        entries[key] = entry
        entry.task.cancel()
    }

    /// Runs `operation` once the current writer for `key` has returned. This
    /// keeps deletion and partial cleanup out of the way of a cancelled
    /// transfer that is still winding down.
    func runExclusive(
        key: ModelDownloadKey,
        operation: @escaping @MainActor (UUID) async -> Void
    ) async {
        while true {
            if let task = entries[key]?.task {
                await task.value
                // A retry waiter may have claimed the cancelled generation
                // between the old task's finish and this wake-up. Wait for
                // that replacement too before taking the exclusive slot.
                continue
            }
            // No writer is live. Consuming this marker makes an exclusive
            // operation win a cancel/retry race without ever overlapping a
            // retry that has already claimed the slot.
            restartAfterCancellation.removeValue(forKey: key)
            await start(key: key, operation: operation)
            return
        }
    }

    /// Creates and awaits the single current writer. The task removes its own
    /// generation before becoming complete and records whether a replacement
    /// waiter is allowed to claim the slot.
    private func start(
        key: ModelDownloadKey,
        operation: @escaping @MainActor (UUID) async -> Void
    ) async {
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.finish(key: key, token: token) }
            await operation(token)
        }
        entries[key] = Entry(token: token, task: task, cancelRequested: false)
        await task.value
    }

    private func finish(key: ModelDownloadKey, token: UUID) {
        guard let entry = entries[key], entry.token == token else { return }
        entries.removeValue(forKey: key)
        if entry.cancelRequested {
            restartAfterCancellation[key] = token
        }
    }
}

@MainActor
extension ModelCatalog {
    /// Cancels a running download and marks it resumable. The coordinator keeps
    /// the cache slot until the dependency call returns; a later Resume then
    /// starts only after the old absolute-path writer has drained.
    func cancelDownload(_ id: String, kind: ModelDownloadKind) {
        guard stopDownload(id, kind: kind) else { return }
        markDownloadPaused(id, kind: kind)
    }

    /// Cancels a transfer whose progress watchdog has expired. The old writer
    /// remains serialized until its dependency call returns.
    @discardableResult
    func cancelStalledDownload(_ id: String, kind: ModelDownloadKind) -> Bool {
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
