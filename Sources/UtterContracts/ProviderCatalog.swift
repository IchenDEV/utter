import Foundation
import UtterRuntime

package struct ProviderDescriptor: Equatable, Sendable {
    package let id: String
    package let legacyIDs: [String]
    package let displayName: String
    package let modelIDs: [String]
    package let artifacts: [ModelArtifact]

    package init(id: String, legacyIDs: [String] = [], displayName: String, modelIDs: [String] = [], artifacts: [ModelArtifact] = []) {
        self.id = id
        self.legacyIDs = legacyIDs
        self.displayName = displayName
        self.modelIDs = modelIDs.isEmpty ? artifacts.map(\.id) : modelIDs
        self.artifacts = artifacts
    }
}

package struct ProviderDefinition<Request, Value> {
    package let descriptor: ProviderDescriptor
    package let create: @MainActor (Request) async throws -> Value

    package init(descriptor: ProviderDescriptor, create: @escaping @MainActor (Request) async throws -> Value) {
        self.descriptor = descriptor
        self.create = create
    }
}

@MainActor
package protocol ProviderCatalog<Request, Value>: AnyObject {
    associatedtype Request
    associatedtype Value
    var descriptors: [ProviderDescriptor] { get }
    func register(_ definition: ProviderDefinition<Request, Value>, scope: PluginScope) throws
    func create(id: String, request: Request) async throws -> Value
}

package enum ProviderCatalogError: Error, Equatable {
    case duplicateIdentifier(String)
    case unknownIdentifier(String)
    case closed
}
