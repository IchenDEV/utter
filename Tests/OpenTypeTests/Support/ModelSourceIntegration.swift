import Foundation
import UtterContracts
import UtterData
import UtterMLX
import UtterModels
import UtterPresentationContracts
import UtterRuntime

@MainActor
final class ModelSourceIntegration {
    let suite: String
    let root: URL
    let defaults: UserDefaults
    let runtime: PluginRuntime
    let settings: AppSettings
    let catalog: any ModelCatalogService
    let storage: any ModelStorageService
    let files: any ModelFilesService

    private init(suite: String, root: URL, defaults: UserDefaults, runtime: PluginRuntime) throws {
        self.suite = suite; self.root = root; self.defaults = defaults; self.runtime = runtime
        settings = AppSettings(service: try runtime.service(DataServices.settings))
        catalog = try runtime.service(ModelServices.catalog)
        storage = try runtime.service(ModelServices.storage)
        files = try runtime.service(ModelServices.files)
    }

    static func start(suite: String = "UtterSourceIntegration-\(UUID().uuidString)",
                      root: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) async throws -> ModelSourceIntegration {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(root.path, forKey: "modelStoragePath")
        defaults.set(false, forKey: "preloadSpeechModelOnLaunch")
        defaults.set(false, forKey: "preloadFormattingModelOnLaunch")
        defaults.set(true, forKey: "hasCompletedOnboarding")
        let artifacts = PluginRegistration(descriptor: PluginDescriptor(id: "source-verification.artifacts",
            requires: [ModelServices.artifacts.required])) { context, _ in
            try context.require(ModelServices.artifacts).register(MLXModelArtifacts.text + MLXModelArtifacts.speech, scope: context.scope)
        }
        let plugins = [DataPlugins.settings(defaults: defaults), DataPlugins.diagnostics(ModelSourceDiagnostics()),
                       ModelPlugins.resourceAccess(), ModelPlugins.artifacts(), ModelPlugins.files(), ModelPlugins.storage(),
                       ModelPlugins.speechProviders(), artifacts, MLXPlugins.modelDownloads(), ModelPlugins.catalog()]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        return try ModelSourceIntegration(suite: suite, root: root, defaults: defaults, runtime: runtime)
    }

    func close(remove: Bool = true) async throws {
        try await runtime.stop()
        if remove {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
}

struct ModelSourceDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }
}
