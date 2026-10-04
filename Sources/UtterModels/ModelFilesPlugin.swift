import Foundation
import UtterContracts
import UtterRuntime

@MainActor
extension ModelPlugins {
    package static func files() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "models.files", requires: [DataServices.settings.required, ModelServices.artifacts.required], provides: [ModelServices.files.reference]
        )) { context, _ in
            let artifacts = try context.require(ModelServices.artifacts)
            let settings = try context.require(DataServices.settings)
            let values = ModelFileSettings(settings.values)
            let observation = settings.observe { values.update($0) }
            try context.scope.onDispose { settings.removeObserver(observation) }
            let files = ConfiguredModelFiles(
                settings: { values.snapshot }, speechRequiredFiles: { artifacts.artifact($0)?.requiredFiles ?? [] }
            )
            try context.provide(ModelServices.files, value: files)
        }
    }
}

private final class ModelFileSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var values: SettingsValues

    init(_ values: SettingsValues) { self.values = values }
    var snapshot: SettingsValues {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
    func update(_ values: SettingsValues) {
        lock.lock()
        defer { lock.unlock() }
        self.values = values
    }
}
