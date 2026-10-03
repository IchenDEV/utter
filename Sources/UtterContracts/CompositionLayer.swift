import Foundation
import UtterRuntime

package struct CompositionLayer {
    package let id: String
    package let plugins: [PluginConfigurationRow]
    package let bindings: [String: String]

    package init(_ id: String, plugins: [PluginConfigurationRow] = [], bindings: [String: String] = [:]) {
        self.id = id
        self.plugins = plugins
        self.bindings = bindings
    }
}

package struct ProviderBindingDescriptor {
    package let capability: String
    package let providerID: String
    package let pluginID: String

    package init(capability: String, providerID: String, pluginID: String) {
        self.capability = capability
        self.providerID = providerID
        self.pluginID = pluginID
    }
}

package struct EffectiveComposition: Equatable {
    package let plugins: [PluginConfigurationRow]
    package let bindings: [String: String]

    package init(plugins: [PluginConfigurationRow], bindings: [String: String]) {
        self.plugins = plugins
        self.bindings = bindings
    }

    package var selections: [PluginSelection] {
        plugins.filter(\.enabled).map { PluginSelection($0.id, configuration: $0.configuration) }
    }

    package var mountedPluginIDs: Set<String> { Set(plugins.filter(\.enabled).map(\.id)) }
}

package enum CompositionError: Error, Equatable {
    case unsupportedVersion(Int)
    case duplicateBundle(String)
    case unknownBundle(String)
    case duplicateRow(layer: String, plugin: String)
    case duplicateProvider(capability: String, provider: String)
    case unknownCapability(String)
    case unknownProvider(capability: String, provider: String)
    case disabledProvider(capability: String, provider: String, plugin: String)
}
