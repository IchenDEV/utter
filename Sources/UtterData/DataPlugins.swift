import Foundation
import UtterContracts
import UtterRuntime

@MainActor
package enum DataPlugins {
    package static func settings(defaults: UserDefaults) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "data.settings", provides: [DataServices.settings.reference])) { context, _ in
            try context.provide(DataServices.settings, value: SettingsStore(defaults: defaults))
        }
    }

    package static func lexicons() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "data.lexicons", provides: [DataServices.lexicons.reference])) { context, _ in
            let url = DataResources.bundle.url(forResource: "IndustryLexicons", withExtension: "json")
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            let catalog = try IndustryLexiconCatalog.decode(Data(contentsOf: url))
            try context.provide(DataServices.lexicons, value: catalog)
        }
    }

    package static func configuration(_ store: CompositionStore) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "data.configuration", provides: [DataServices.configuration.reference])) { context, _ in
            try context.provide(DataServices.configuration, value: store)
        }
    }
}
