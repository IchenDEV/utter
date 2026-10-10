import Foundation
import UtterContracts
import UtterRuntime

package final class ModelArtifactRegistry: ModelArtifactService, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String: ModelArtifact] = [:]
    private var closed = false

    package init() {}
    package var artifacts: [ModelArtifact] {
        lock.lock()
        defer { lock.unlock() }
        return rows.values.sorted { ($0.rank, $0.id) < ($1.rank, $1.id) }
    }
    package func artifact(_ id: String) -> ModelArtifact? {
        lock.lock()
        defer { lock.unlock() }
        return rows[id]
    }

    @MainActor
    package func register(_ artifact: ModelArtifact, scope: PluginScope) throws {
        guard artifact.memoryRequirements?.isValid ?? true else {
            throw ModelArtifactError.invalidMemoryRequirements(artifact.id)
        }
        for file in artifact.requiredFiles {
            guard !file.isEmpty, !file.hasPrefix("/"), !file.split(separator: "/").contains("..") else {
                throw ModelArtifactError.invalidRequiredFile(file)
            }
        }
        lock.lock()
        if closed { lock.unlock(); throw ModelArtifactError.closed }
        if rows[artifact.id] != nil { lock.unlock(); throw ModelArtifactError.duplicateID(artifact.id) }
        rows[artifact.id] = artifact
        lock.unlock()
        do {
            try scope.onDispose { self.remove(artifact.id) }
        } catch {
            remove(artifact.id)
            throw error
        }
    }

    package func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }
    private func remove(_ id: String) {
        lock.lock()
        rows.removeValue(forKey: id)
        lock.unlock()
    }
}
