import Foundation

@MainActor
package final class PluginRuntime {
    package enum State: Equatable { case stopped, starting, ready, stopping, failed }

    package private(set) var state: State = .stopped
    package private(set) var generation: UUID?
    private let catalog: PluginCatalog
    private var store = ServiceStore()
    private var scopes: [PluginScope] = []
    private var activationTask: Task<Void, Error>?
    private var shutdownTask: Task<Void, Error>?

    package init(catalog: PluginCatalog) { self.catalog = catalog }

    package func start(_ selections: [PluginSelection]) async throws {
        guard activationTask == nil, shutdownTask == nil,
              state == .stopped || state == .failed else {
            throw PluginRuntimeError.transitionInProgress
        }
        guard scopes.isEmpty else { throw PluginRuntimeError.cleanupPending }
        let plugins = try catalog.orderedRegistrations(selections)
        try Task.checkCancellation()
        let generation = UUID()
        self.generation = generation
        store = ServiceStore()
        state = .starting
        let task = Task { try await activate(plugins, generation: generation) }
        activationTask = task
        defer { activationTask = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    package func service<Value>(_ key: ServiceKey<Value>) throws -> Value {
        guard state == .ready else { throw PluginRuntimeError.notReady }
        guard let value = try store.resolve(key) else {
            throw PluginRuntimeError.missingService(plugin: "runtime", service: key.name)
        }
        return value
    }

    package func stop() async throws {
        if let task = shutdownTask { return try await task.value }
        if let task = activationTask {
            task.cancel()
            for scope in scopes { scope.revoke() }
            _ = await task.result
        }
        if let task = shutdownTask { return try await task.value }
        guard state != .stopped else { return }
        state = .stopping
        for scope in scopes { scope.revoke() }
        let task = Task {
            let failures = await disposeScopes()
            state = failures.isEmpty ? .stopped : .failed
            if scopes.isEmpty { generation = nil }
            if !failures.isEmpty { throw PluginShutdownFailure(failures: failures) }
        }
        shutdownTask = task
        defer { shutdownTask = nil }
        try await task.value
    }

    private func activate(_ plugins: [PlannedPlugin], generation: UUID) async throws {
        var currentID = "runtime"
        do {
            for plugin in plugins {
                currentID = plugin.selection.id
                try Task.checkCancellation()
                let descriptor = plugin.registration.descriptor
                let scope = PluginScope(pluginID: descriptor.id)
                scopes.append(scope)
                let context = PluginContext(descriptor: descriptor, generation: generation, scope: scope, store: store)
                try await plugin.registration.activate(context, plugin.selection.configuration)
                try Task.checkCancellation()
                try context.checkRegistrations()
            }
            state = .ready
        } catch {
            for scope in scopes { scope.revoke() }
            let failures = await Task { await disposeScopes() }.value
            state = .failed
            if scopes.isEmpty { self.generation = nil }
            throw PluginActivationFailure(pluginID: currentID, cause: error, cleanupFailures: failures)
        }
    }

    private func disposeScopes() async -> [PluginDisposalFailure] {
        var failures: [PluginDisposalFailure] = []
        for scope in scopes.reversed() {
            failures.append(contentsOf: await scope.dispose())
            if !scope.hasPendingDisposal {
                store.remove(owner: scope.pluginID)
                scopes.removeAll { $0 === scope }
            }
        }
        return failures
    }
}
