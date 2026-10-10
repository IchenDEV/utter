import Foundation
import HuggingFace
import UtterContracts
import UtterRuntime

@MainActor
extension MLXPlugins {
    package static func modelDownloads() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "models.mlx-downloads", requires: [ModelServices.resourceAccess.required],
            provides: [ModelServices.textDownloads.reference]
        )) { context, _ in
            let service = MLXTextModelDownloads(access: try context.require(ModelServices.resourceAccess))
            try context.provide(ModelServices.textDownloads, value: service)
        }
    }
}

private struct MLXTextModelDownloads: TextModelDownloadService {
    let access: any ModelResourceAccess
    func download(_ id: String, downloadBase: URL, cacheDirectory: URL,
                  progress: @escaping @Sendable (Progress) -> Void) async throws {
        try await MLXModelDownloads.download(id, downloadBase: downloadBase,
                                            cache: HubCache(cacheDirectory: cacheDirectory), progress: progress)
    }
    func validate(_ directory: URL) async throws {
        try await access.withAccess { try await MLXModelDownloads.validate(directory) }
    }
}
