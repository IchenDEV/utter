import Foundation

@MainActor
final class IngressTasks {
    private var closed = false
    private var tasks: [UUID: Task<Void, Never>] = [:]
    func launch(_ operation: @escaping @MainActor () async -> Void) {
        guard !closed else { return }
        let id = UUID()
        tasks[id] = Task { [weak self] in
            defer { self?.tasks[id] = nil }
            guard self?.closed == false, !Task.isCancelled else { return }
            await operation()
        }
    }
    func revoke() {
        closed = true
        for task in tasks.values { task.cancel() }
    }
    func close() async {
        revoke()
        for task in Array(tasks.values) { await task.value }
    }
}
