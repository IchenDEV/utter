import Foundation

@MainActor
package final class PluginContext {
    package let descriptor: PluginDescriptor
    package let generation: UUID
    package let scope: PluginScope
    private let store: ServiceStore

    init(descriptor: PluginDescriptor, generation: UUID, scope: PluginScope, store: ServiceStore) {
        self.descriptor = descriptor
        self.generation = generation
        self.scope = scope
        self.store = store
    }

    package var isReady: Bool { scope.isActive && store.isReady }

    package var isCurrent: Bool { scope.isActive }

    package func require<Value>(_ key: ServiceKey<Value>) throws -> Value {
        try checkLookup(key.reference)
        guard let value = try store.resolve(key) else {
            throw PluginRuntimeError.missingService(plugin: descriptor.id, service: key.name)
        }
        return value
    }

    package func optional<Value>(_ key: ServiceKey<Value>) throws -> Value? {
        try checkLookup(key.reference)
        return try store.resolve(key)
    }

    package func provide<Value>(_ key: ServiceKey<Value>, value: Value) throws {
        guard isCurrent else { throw PluginRuntimeError.scopeClosed(descriptor.id) }
        guard descriptor.provides.contains(key.reference) else {
            throw PluginRuntimeError.undeclaredRegistration(plugin: descriptor.id, service: key.name)
        }
        try store.provide(key, value: value, owner: descriptor.id)
    }

    private func checkLookup(_ reference: ServiceReference) throws {
        guard isCurrent else { throw PluginRuntimeError.scopeClosed(descriptor.id) }
        guard descriptor.requires.contains(where: { $0.service == reference }) else {
            throw PluginRuntimeError.undeclaredLookup(plugin: descriptor.id, service: reference.name)
        }
    }

    func checkRegistrations() throws {
        for service in descriptor.provides {
            guard store.contains(service, owner: descriptor.id) else {
                throw PluginRuntimeError.missingRegistration(plugin: descriptor.id, service: service.name)
            }
        }
    }
}
