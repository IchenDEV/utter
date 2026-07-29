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
        operation: @escaping @MainActor () async -> Void
    ) async {
        if let existing = entries[key] {
            await existing.task.value
            return
        }

        let token = UUID()
        let task = Task { @MainActor in
            await operation()
        }
        entries[key] = Entry(token: token, task: task)
        await task.value

        if entries[key]?.token == token {
            entries.removeValue(forKey: key)
        }
    }

    func cancel(_ key: ModelDownloadKey) {
        entries[key]?.task.cancel()
    }
}

@MainActor
extension ModelCatalog {
    func cancelDownload(_ id: String, kind: ModelDownloadKind) {
        downloadTasks.cancel(ModelDownloadKey(kind: kind, modelID: id))
    }
}
