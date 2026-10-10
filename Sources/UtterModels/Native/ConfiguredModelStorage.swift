import Foundation
import UtterContracts

package struct ConfiguredModelStorage {
    private let settings: () -> SettingsValues
    package init(settings: @escaping () -> SettingsValues) { self.settings = settings }

    package var root: URL { ConfiguredModelFiles.storageRoot(settings: settings()) }
    package var whisperRepoCacheRoot: URL { root.appendingPathComponent(ModelDownloadRecovery.whisperRepositoryRelativePath) }
    package func generationStaging(for token: UUID) -> ModelDownloadStaging {
        ModelStorage.generationStaging(for: token, storageRoot: root)
    }
    package func whisperVariantDir(_ id: String) -> URL {
        ModelStorage.whisperVariantDir(id, downloadBase: root)
    }
    package func hubModelRepoDir(_ id: String) -> URL {
        ModelStorage.hubModelRepoDir(id, downloadBase: root)
    }
    package func localWhisperURL(_ id: String) -> URL? { settings().localWhisperModelPaths[id].map(expandedURL) }
    package func localLLMURL(_ id: String) -> URL? { settings().localLLMModelPaths[id].map(expandedURL) }
    package func llmRepoDir(_ id: String) -> URL? { existing(localLLMURL(id) ?? hubModelRepoDir(id)) }
    package func installedLLMURL(_ id: String) -> URL? {
        guard let url = llmRepoDir(id), ModelAssets.llmRepoIsComplete(at: url) else { return nil }
        return url
    }
    package func asrRepoDir(_ id: String) -> URL? { existing(hubModelRepoDir(id)) }

    private func expandedURL(_ path: String) -> URL { URL(fileURLWithPath: NSString(string: path).expandingTildeInPath) }
    private func existing(_ url: URL) -> URL? { FileManager.default.fileExists(atPath: url.path) ? url : nil }
}
