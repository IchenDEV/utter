import Foundation
import UtterContracts
import UtterRuntime

@MainActor
extension ModelPlugins {
    package static func storage() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(id: "models.storage", requires: [DataServices.settings.required],
            provides: [ModelServices.storage.reference])) { context, _ in
            try context.provide(ModelServices.storage, value: NativeModelStorage(settings: try context.require(DataServices.settings),
                isReady: { context.isReady }))
        }
    }
}

@MainActor
private final class NativeModelStorage: ModelStorageService {
    private let storage: ConfiguredModelStorage
    private let isReady: () -> Bool
    init(settings: any SettingsService, isReady: @escaping () -> Bool) {
        storage = ConfiguredModelStorage(settings: { settings.values })
        self.isReady = isReady
    }
    var root: URL { storage.root }
    var defaultRoot: URL { DataLocations.models }
    var device: DeviceDisplayInformation {
        let info = DeviceCapability.current
        return DeviceDisplayInformation(chip: info.chipDisplayName, ram: info.ramDisplayText,
            gpu: info.gpuDisplayText, disk: info.diskAvailableText)
    }
    func localWhisperURL(_ id: String) -> URL? { isReady() ? storage.localWhisperURL(id) : nil }
    func localLLMURL(_ id: String) -> URL? { isReady() ? storage.localLLMURL(id) : nil }
    func directorySize(at url: URL) -> Int64 { isReady() ? ModelStorage.directorySize(at: url) : 0 }
    func whisperModelIsComplete(at url: URL) -> Bool { isReady() && ModelAssets.whisperModelIsComplete(at: url) }
    func llmRepoIsComplete(at url: URL) -> Bool { isReady() && ModelAssets.llmRepoIsComplete(at: url) }
    func estimatedDownloadBytes(from text: String) -> Int64? { ModelCatalog.estimatedDownloadBytes(from: text) }
}
