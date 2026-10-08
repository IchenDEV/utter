import Foundation
import UtterContracts

extension ModelCatalog {
    func publish(_ prepared: [PreparedModelGeneration], key: ModelDownloadKey, token: UUID) async throws -> Bool {
        try await access.withAccess {
            try await MainActor.run {
                guard !self.closed, !Task.isCancelled else { throw CancellationError() }
                return try self.downloadTasks.publishIfCurrent(key, token: token) {
                    for generation in prepared { try ModelStorage.publishPreparedGeneration(generation) }
                }
            }
        }
    }

    func removeFiles(_ operation: @escaping @MainActor () -> Void) async {
        do {
            try await access.withAccess {
                await MainActor.run {
                    guard !self.closed, !Task.isCancelled else { return }
                    operation()
                }
            }
        } catch is CancellationError {
        } catch {
            log.error("[ModelCatalog] Model maintenance failed: \(error.localizedDescription)")
        }
    }
}
