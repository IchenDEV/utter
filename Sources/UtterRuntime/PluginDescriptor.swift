import Foundation

package struct PluginDescriptor {
    package let id: String
    package let schemaVersion: Int
    package let requires: [ServiceRequirement]
    package let provides: [ServiceReference]

    package init(
        id: String,
        schemaVersion: Int = 1,
        requires: [ServiceRequirement] = [],
        provides: [ServiceReference] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.requires = requires
        self.provides = provides
    }
}

package struct PluginSelection: Equatable {
    package let id: String
    package let configuration: [String: ConfigurationValue]

    package init(_ id: String, configuration: [String: ConfigurationValue] = [:]) {
        self.id = id
        self.configuration = configuration
    }
}

@MainActor
package struct PluginRegistration {
    package let descriptor: PluginDescriptor
    let validateConfiguration: ([String: ConfigurationValue]) throws -> Void
    let activate: (PluginContext, [String: ConfigurationValue]) async throws -> Void

    package init(
        descriptor: PluginDescriptor,
        validate: @escaping ([String: ConfigurationValue]) throws -> Void = { configuration in
            guard configuration.isEmpty else {
                throw PluginRuntimeError.invalidConfiguration("This plugin has no configuration fields")
            }
        },
        activate: @escaping (PluginContext, [String: ConfigurationValue]) async throws -> Void
    ) {
        self.descriptor = descriptor
        self.validateConfiguration = validate
        self.activate = activate
    }
}

@MainActor
package struct PluginCatalog {
    private let registrations: [String: PluginRegistration]

    package init(_ registrations: [PluginRegistration]) throws {
        var indexed: [String: PluginRegistration] = [:]
        for registration in registrations {
            let id = registration.descriptor.id
            guard !id.isEmpty else { throw PluginRuntimeError.invalidPluginID(id) }
            guard indexed[id] == nil else { throw PluginRuntimeError.duplicatePlugin(id) }
            indexed[id] = registration
        }
        self.registrations = indexed
    }

    package var descriptors: [PluginDescriptor] {
        registrations.values.map(\.descriptor).sorted { $0.id < $1.id }
    }

    func registration(_ id: String) throws -> PluginRegistration {
        guard let registration = registrations[id] else { throw PluginRuntimeError.unknownPlugin(id) }
        return registration
    }

    package func validate(_ selections: [PluginSelection]) throws -> [PluginDescriptor] {
        try orderedRegistrations(selections).map { $0.registration.descriptor }
    }
}
