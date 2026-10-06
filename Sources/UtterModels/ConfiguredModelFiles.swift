import Foundation
import UtterContracts

package struct ConfiguredModelFiles: ModelFilesService {
    private let settings: @Sendable () -> SettingsValues
    private let requirements: @Sendable (String) -> [String]

    package init(
        settings: @escaping @Sendable () -> SettingsValues,
        speechRequiredFiles: @escaping @Sendable (String) -> [String]
    ) {
        self.settings = settings
        requirements = speechRequiredFiles
    }

    package static func storageRoot(settings: SettingsValues) -> URL {
        #if os(iOS)
        // iOS container paths can change after an app update or restore.
        return DataLocations.models
        #else
        guard !settings.modelStoragePath.isEmpty else { return DataLocations.models }
        return expandedURL(settings.modelStoragePath)
        #endif
    }

    package static func repositoryDirectory(_ id: String, storageRoot: URL) -> URL {
        storageRoot.appendingPathComponent("models", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }

    package func installedTextModelURL(_ id: String) -> URL? {
        let values = settings()
        let url = values.localLLMModelPaths[id].map(Self.expandedURL)
            ?? Self.repositoryDirectory(id, storageRoot: Self.storageRoot(settings: values))
        return ModelAssets.llmRepoIsComplete(at: url) ? url : nil
    }

    package func installedSpeechModelURL(_ id: String) -> URL? {
        guard !requirements(id).isEmpty else { return nil }
        let url = Self.repositoryDirectory(id, storageRoot: Self.storageRoot(settings: settings()))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    package func speechRequiredFiles(_ id: String) -> [String] { requirements(id) }
    package func textModelIsComplete(at url: URL) -> Bool { ModelAssets.llmRepoIsComplete(at: url) }

    package func installedWhisperURL(_ id: String) -> URL? {
        settings().localWhisperModelPaths[id].map(Self.expandedURL)
    }

    package func whisperVariantURL(_ id: String) -> URL {
        Self.repositoryDirectory("argmaxinc/whisperkit-coreml", storageRoot: Self.storageRoot(settings: settings()))
            .appendingPathComponent(id, isDirectory: true)
    }

    package func whisperModelIsComplete(at url: URL) -> Bool { ModelAssets.whisperModelIsComplete(at: url) }

    private static func expandedURL(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
}
