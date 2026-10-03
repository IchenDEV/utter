import Foundation

@MainActor
package final class PluginScope {
    private struct Effect {
        let id: UUID
        let dispose: () async throws -> Void
    }

    package let pluginID: String
    package private(set) var isActive = true
    private var effects: [Effect] = []
    private var cancellations: [UUID: () -> Void] = [:]

    init(pluginID: String) { self.pluginID = pluginID }

    package func onDispose(_ dispose: @escaping () async throws -> Void) throws {
        guard isActive else { throw PluginRuntimeError.scopeClosed(pluginID) }
        effects.append(Effect(id: UUID(), dispose: dispose))
    }

    @discardableResult
    package func task(_ operation: @escaping () async -> Void) throws -> Task<Void, Never> {
        guard isActive else { throw PluginRuntimeError.scopeClosed(pluginID) }
        let task = Task { await operation() }
        let id = UUID()
        cancellations[id] = { task.cancel() }
        try onDispose { [self] in
            task.cancel()
            await task.value
            cancellations.removeValue(forKey: id)
        }
        return task
    }

    package func acquire<Value>(
        _ operation: @escaping () async throws -> Value,
        dispose: @escaping (Value) async throws -> Void
    ) async throws -> Value {
        guard isActive else { throw PluginRuntimeError.scopeClosed(pluginID) }
        let task = Task { try await operation() }
        let id = UUID()
        cancellations[id] = { task.cancel() }
        try onDispose { [self] in
            task.cancel()
            if case .success(let value) = await task.result { try await dispose(value) }
            cancellations.removeValue(forKey: id)
        }
        return try await withTaskCancellationHandler {
            let value = try await task.value
            try Task.checkCancellation()
            guard isActive else { throw CancellationError() }
            return value
        } onCancel: {
            task.cancel()
        }
    }

    func revoke() {
        isActive = false
        for cancel in cancellations.values { cancel() }
    }

    var hasPendingDisposal: Bool { !effects.isEmpty }

    func dispose() async -> [PluginDisposalFailure] {
        revoke()
        var failures: [PluginDisposalFailure] = []
        for effect in effects.reversed() {
            do {
                try await effect.dispose()
                effects.removeAll { $0.id == effect.id }
            } catch {
                failures.append(PluginDisposalFailure(pluginID: pluginID, cause: error))
            }
        }
        return failures
    }
}
