import Foundation

enum ModelDownloadKind: Hashable, Sendable {
    case whisper
    case llm
    case asr
}

struct ModelDownloadKey: Hashable, Sendable {
    let kind: ModelDownloadKind
    let modelID: String
}

/// Arbitrates model generations and publication. Each download operation owns
/// a generation-scoped staging root, so a cancelled writer can finish against
/// its old absolute paths while a replacement proceeds in a different root.
/// Publication still has to go through publishIfCurrent: the token check and
/// the short atomic promotion are one MainActor turn, and therefore cannot
/// race Cancel or Delete. Large candidate/backup preparation happens before
/// that turn on a detached task.
@MainActor
final class ModelDownloadTasks {
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
    }

    private struct RetiredEntry {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var entries: [ModelDownloadKey: Entry] = [:]
    /// Retired writers are retained until their dependency operation returns,
    /// but no longer own the key. Their staging roots are cleaned by the
    /// operation's defer, never by looking for a missing current token.
    private var retiredEntries: [ModelDownloadKey: [RetiredEntry]] = [:]

    /// Runs `operation` as the single writer for `key`.
    ///
    /// - Duplicate request while a live run is active: joins it, does not restart.
    /// - Request after cancellation: starts a new generation immediately;
    ///   the old writer remains retained as a retired task and writes only to
    ///   its own staging root.
    func run(
        key: ModelDownloadKey,
        operation: @escaping @MainActor (UUID) async -> Void
    ) async {
        if let existing = entries[key] {
            let observedToken = existing.token
            await existing.task.value
            // A duplicate that joined before cancellation remains a duplicate;
            // if a real Resume claimed a replacement, join that generation.
            if let replacement = entries[key], replacement.token != observedToken {
                await replacement.task.value
            }
            return
        }

        await start(key: key, operation: operation)
    }

    /// True while `token` still owns the current generation for `key`. A
    /// cancelled writer is removed from this map immediately, so it cannot
    /// publish progress, terminal state, or a model.
    func isCurrent(_ key: ModelDownloadKey, token: UUID) -> Bool {
        guard let entry = entries[key] else { return false }
        return entry.token == token
    }

    func isActive(_ key: ModelDownloadKey) -> Bool {
        entries[key] != nil
    }

    /// Retires the current generation immediately. Its task is retained until
    /// return, but Resume may create a new isolated staging generation without
    /// waiting for a dependency that ignores cancellation.
    func cancel(_ key: ModelDownloadKey) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        retiredEntries[key, default: []].append(
            RetiredEntry(token: entry.token, task: entry.task)
        )
        entry.task.cancel()
    }

    /// Runs `operation` once the current publisher for `key` has returned.
    /// Retired generations are isolated under `.utter-generations/<token>`;
    /// a waiter observes the current-entry map rather than awaiting a task
    /// handle captured before Cancel, so a Delete already in flight can also
    /// proceed after that current entry is retired.
    func runExclusive(
        key: ModelDownloadKey,
        operation: @escaping @MainActor (UUID) async -> Void
    ) async {
        while entries[key] != nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        await start(key: key, operation: operation)
    }

    /// Executes only the short prepared commit while token still owns the live
    /// generation. Because this method is MainActor-isolated,
    /// Cancel/Delete cannot interleave between validation and atomic
    /// promotion; expensive tree preparation must happen before this call.
    @discardableResult
    func publishIfCurrent(
        _ key: ModelDownloadKey,
        token: UUID,
        publish: () throws -> Void
    ) rethrows -> Bool {
        guard isCurrent(key, token: token) else { return false }
        try publish()
        return true
    }

    /// Creates and awaits the single current writer. A retired writer's
    /// `finish` must not clear a replacement entry, so token matching is used
    /// for both current and retired bookkeeping.
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
        if let entry = entries[key], entry.token == token {
            entries.removeValue(forKey: key)
            return
        }
        guard var retired = retiredEntries[key] else { return }
        retired.removeAll { $0.token == token }
        if retired.isEmpty {
            retiredEntries.removeValue(forKey: key)
        } else {
            retiredEntries[key] = retired
        }
    }
}

@MainActor
extension ModelCatalog {
    /// Cancels a running download and marks it resumable. Its generation root
    /// remains owned by the still-running operation; a later Resume gets a
    /// fresh root immediately.
    func cancelDownload(_ id: String, kind: ModelDownloadKind) {
        guard stopDownload(id, kind: kind) else { return }
        markDownloadPaused(id, kind: kind)
    }

    /// Cancels a transfer whose progress watchdog has expired.
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
