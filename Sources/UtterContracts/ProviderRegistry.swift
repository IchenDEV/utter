import Foundation
import UtterRuntime

@MainActor
package final class ProviderRegistry<Request, Value>: ProviderCatalog {
    private let definitions = ContributionRegistry<ProviderDefinition<Request, Value>>()
    private var closed = false

    package init() {}

    package var descriptors: [ProviderDescriptor] {
        definitions.ids.compactMap { definitions.value(for: $0)?.descriptor }
    }

    package func register(_ definition: ProviderDefinition<Request, Value>, scope: PluginScope) throws {
        guard !closed else { throw ProviderCatalogError.closed }
        let proposed = [definition.descriptor.id] + definition.descriptor.legacyIDs
        guard Set(proposed).count == proposed.count else {
            throw ProviderCatalogError.duplicateIdentifier(definition.descriptor.id)
        }
        let existing = Set(descriptors.flatMap { [$0.id] + $0.legacyIDs })
        if let duplicate = proposed.first(where: { existing.contains($0) }) {
            throw ProviderCatalogError.duplicateIdentifier(duplicate)
        }
        let scoped = ProviderDefinition<Request, Value>(descriptor: definition.descriptor, reset: {
            guard scope.isActive else { throw ProviderCatalogError.closed }
            try await scope.run { try await definition.reset() }
        }) { request in
            guard scope.isActive else { throw ProviderCatalogError.closed }
            let value = try await scope.run { try await definition.create(request) }
            guard scope.isActive else { throw ProviderCatalogError.closed }
            return value
        }
        try definitions.contribute(definition.descriptor.id, value: scoped, scope: scope)
    }

    package func create(id: String, request: Request) async throws -> Value {
        guard !closed else { throw ProviderCatalogError.closed }
        guard let descriptor = descriptors.first(where: { $0.id == id || $0.legacyIDs.contains(id) }),
              let definition = definitions.value(for: descriptor.id) else {
            throw ProviderCatalogError.unknownIdentifier(id)
        }
        try Task.checkCancellation()
        let value = try await definition.create(request)
        try Task.checkCancellation()
        guard !closed, definitions.value(for: descriptor.id) != nil else { throw ProviderCatalogError.closed }
        return value
    }

    package func close() { closed = true }

    package func reset(id: String) async throws {
        guard !closed else { throw ProviderCatalogError.closed }
        guard let descriptor = descriptors.first(where: { $0.id == id || $0.legacyIDs.contains(id) }),
              let definition = definitions.value(for: descriptor.id) else {
            throw ProviderCatalogError.unknownIdentifier(id)
        }
        try Task.checkCancellation()
        try await definition.reset()
        guard !closed else { throw ProviderCatalogError.closed }
    }
}
