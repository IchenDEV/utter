import Foundation

package struct ServiceKey<Value> {
    package let name: String

    package init(_ name: String) { self.name = name }

    package var reference: ServiceReference {
        ServiceReference(name: name, type: ObjectIdentifier(Value.self))
    }

    package var required: ServiceRequirement { ServiceRequirement(reference, optional: false) }
    package var optional: ServiceRequirement { ServiceRequirement(reference, optional: true) }
}

package struct ServiceReference: Hashable {
    package let name: String
    let type: ObjectIdentifier
}

package struct ServiceRequirement: Equatable {
    package let service: ServiceReference
    package let isOptional: Bool

    init(_ service: ServiceReference, optional: Bool) {
        self.service = service
        self.isOptional = optional
    }
}

@MainActor
final class ServiceStore {
    var isReady = false
    private struct Entry {
        let owner: String
        let reference: ServiceReference
        let value: Any
    }

    private var entries: [String: Entry] = [:]

    func provide<Value>(_ key: ServiceKey<Value>, value: Value, owner: String) throws {
        guard entries[key.name] == nil else {
            throw PluginRuntimeError.duplicateService(key.name)
        }
        entries[key.name] = Entry(owner: owner, reference: key.reference, value: value)
    }

    func resolve<Value>(_ key: ServiceKey<Value>) throws -> Value? {
        guard let entry = entries[key.name] else { return nil }
        guard entry.reference == key.reference, let value = entry.value as? Value else {
            throw PluginRuntimeError.serviceTypeMismatch(key.name)
        }
        return value
    }

    func contains(_ service: ServiceReference, owner: String) -> Bool {
        entries[service.name].map { $0.reference == service && $0.owner == owner } ?? false
    }

    func remove(owner: String) { entries = entries.filter { $0.value.owner != owner } }
}
