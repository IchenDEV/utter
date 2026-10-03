import Foundation

@MainActor
extension HotkeyManager {
    func ownedTask(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.ownedTasks.removeValue(forKey: id) }
            await operation()
        }
        ownedTasks[id] = task
        return task
    }

    func scheduleTrustRetry(after seconds: UInt64) {
        retryTask?.cancel()
        retryTask = ownedTask { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, !Task.isCancelled, !self.isClosed else { return }
            self.retryIfTrusted()
        }
    }

    package func close() async {
        stop()
        for task in Array(ownedTasks.values) { await task.value }
    }
}
