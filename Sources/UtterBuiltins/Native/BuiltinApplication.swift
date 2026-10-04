import Foundation
import UtterContracts
import UtterData
import UtterRuntime

@MainActor
package final class BuiltinApplication {
    package let runtime: PluginRuntime
    package let configuration: CompositionStore
    package let compositionFailure: Error?
    private let settings: any SettingsService
    private let diagnostics: any DiagnosticsService
    private var settingsObservation: UUID?

    private init(runtime: PluginRuntime, configuration: CompositionStore, settings: any SettingsService,
                 failure: Error?, diagnostics: any DiagnosticsService) {
        self.runtime = runtime; self.configuration = configuration
        self.settings = settings; compositionFailure = failure; self.diagnostics = diagnostics
    }

    package static func start(defaults: UserDefaults = .standard, directory: URL? = nil,
                              additional: [PluginRegistration] = [],
                              replacements: [PluginRegistration] = []) async throws -> BuiltinApplication {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent(ProductBrand.applicationSupportDirectoryName, isDirectory: true)
        let settings = SettingsStore(defaults: defaults)
        var configuration: CompositionStore?
        let registrations = try BuiltinPlugins.registrations(defaults: defaults, directory: directory, settings: settings,
            configuration: {
                guard let configuration else { throw CompositionStoreError.notLoaded }
                return configuration
            }, additional: additional, replacements: replacements)
        let catalog = try PluginCatalog(registrations)
        let resolver = try CompositionResolver(catalog: catalog, bundles: BuiltinCompositions.bundles(registrations),
                                             providers: BuiltinCompositions.providers)
        let store = try CompositionStore(fileURL: directory.appendingPathComponent("plugins.json"),
            resolver: resolver, shipped: BuiltinCompositions.shipped, legacy: BuiltinCompositions.legacy(settings.values))
        configuration = store
        let selections: [PluginSelection]
        let failure: Error?
        do { selections = try store.load().selections; failure = nil }
        catch {
            failure = error
            selections = registrations.filter { BuiltinCompositions.recoveryIDs.contains($0.descriptor.id) }
                .map { PluginSelection($0.descriptor.id) }
        }
        let runtime = PluginRuntime(catalog: catalog)
        try await runtime.start(selections)
        let application = BuiltinApplication(runtime: runtime, configuration: store, settings: settings,
            failure: failure, diagnostics: try runtime.service(IntegrationServices.diagnostics))
        if failure == nil {
            application.settingsObservation = settings.observe { [weak application] values in
                guard let application else { return }
                do { try store.updateLegacy(BuiltinCompositions.legacy(values)) }
                catch { application.diagnostics.error("Provider selection unavailable: \(error.localizedDescription)") }
            }
        }
        return application
    }

    package func stop() async throws {
        if let settingsObservation { settings.removeObserver(settingsObservation) }
        settingsObservation = nil
        try await runtime.stop()
    }
}
