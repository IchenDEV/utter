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
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(pluginID: String) { self.pluginID = pluginID }

    package func onDispose(_ dispose: @escaping () async throws -> Void) throws {
        guard isActive else { throw PluginRuntimeError.scopeClosed(pluginID) }
        effects.append(Effect(id: UUID(), dispose: dispose))
    }

    package func own(_ task: Task<Void, Never>) throws {
        guard isActive else {
            task.cancel()
            throw PluginRuntimeError.scopeClosed(pluginID)
        }
        let id = UUID()
        tasks[id] = task
        try onDispose { [self] in
            task.cancel()
            await task.value
            tasks.removeValue(forKey: id)
        }
    }

    func revoke() {
        isActive = false
        for task in tasks.values { task.cancel() }
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
