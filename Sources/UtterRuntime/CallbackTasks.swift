import Foundation

/// Owns actor hops from dependency callbacks that may arrive on any thread.
package final class CallbackTasks: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var tasks: [UUID: Task<Void, Never>] = [:]

    package init() {}

    package func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        let id = UUID()
        let task = Task { @MainActor [self] in
            defer { finished(id) }
            guard isActive, !Task.isCancelled else { return }
            await operation()
        }
        tasks[id] = task
        lock.unlock()
    }

    package func revoke() {
        lock.lock()
        closed = true
        let pending = Array(tasks.values)
        lock.unlock()
        for task in pending { task.cancel() }
    }

    package func close() async {
        revoke()
        let pending = snapshot()
        for task in pending { await task.value }
    }

    package func drain() async {
        while true {
            let pending = snapshot()
            if pending.isEmpty { return }
            for task in pending { await task.value }
        }
    }

    private var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
    }
    private func snapshot() -> [Task<Void, Never>] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tasks.values)
    }
    private func finished(_ id: UUID) {
        lock.lock()
        tasks.removeValue(forKey: id)
        lock.unlock()
    }
}
