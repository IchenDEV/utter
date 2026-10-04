import Foundation
import UtterContracts
import UtterRuntime

@MainActor
package enum DataPlugins {
    package static func integrationClients(defaults: UserDefaults) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "data.integration-clients", requires: [IntegrationServices.diagnostics.optional],
            provides: [IntegrationServices.clients.reference]
        )) { context, _ in
            let diagnostics = try context.optional(IntegrationServices.diagnostics)
            let registry = IntegrationClientRegistry(defaults: defaults, reportError: { diagnostics?.error($0) })
            try context.scope.onDispose { registry.close() }
            try context.provide(IntegrationServices.clients, value: registry)
        }
    }

    package static func notifications() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "data.notifications", provides: [DataServices.notifications.reference])) { context, _ in
            try context.provide(DataServices.notifications, value: StateNotifications())
        }
    }

    package static func correctionClassification() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "data.correction-classification", provides: [DataServices.correctionClassification.reference]
        )) { context, _ in
            try context.provide(DataServices.correctionClassification, value: BuiltinCorrectionClassification())
        }
    }

    package static func credentials() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "data.credentials", requires: [DataServices.settings.required], provides: [DataServices.credentials.reference]
        )) { context, _ in
            try context.provide(DataServices.credentials, value: SettingsCredentialsService(settings: try context.require(DataServices.settings)))
        }
    }

    package static func diagnostics(_ service: any DiagnosticsService) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "data.diagnostics", provides: [IntegrationServices.diagnostics.reference])) { context, _ in
            try context.provide(IntegrationServices.diagnostics, value: service)
        }
    }

    package static func dictionary(directoryURL: URL) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "data.dictionary", requires: [IntegrationServices.diagnostics.optional],
            provides: [DataServices.dictionary.reference, DataServices.dictionarySnapshot.reference]
        )) { context, _ in
            let diagnostics = try context.optional(IntegrationServices.diagnostics)
            let store = DictionaryStore(directoryURL: directoryURL, reportError: { diagnostics?.error($0) })
            try context.provide(DataServices.dictionary, value: store)
            try context.provide(DataServices.dictionarySnapshot, value: store)
        }
    }

    package static func memory() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "data.memory", requires: [DataServices.history.required], provides: [DataServices.memory.reference])) { context, _ in
            let history = try context.require(DataServices.history)
            try context.provide(DataServices.memory, value: HistoryMemoryService(history: history))
        }
    }

    package static func history(directoryURL: URL, reportError: @escaping (String) -> Void) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "data.history", requires: [DataServices.settings.required, DataServices.notifications.required], provides: [DataServices.history.reference])) { context, _ in
            let settings = try context.require(DataServices.settings)
            let store = HistoryStore(directoryURL: directoryURL, retention: { settings.values.historyRetention }, reportError: reportError, notifications: try context.require(DataServices.notifications))
            try context.provide(DataServices.history, value: store)
        }
    }

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
