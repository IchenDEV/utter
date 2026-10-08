import Foundation
import Hub
import HuggingFace
import MLXLLM
import MLXLMCommon

package enum MLXModelDownloads {
    package static func download(
        _ id: String, downloadBase: URL, cache: HubCache,
        progress: @escaping @Sendable (Progress) -> Void
    ) async throws {
        _ = try await MLXLMCommon.resolve(
            configuration: ModelConfiguration(id: id),
            from: MLXModelLoading.downloader(downloadBase: downloadBase, cache: cache),
            useLatest: false, progressHandler: progress
        )
    }

    package static func validate(_ directory: URL) async throws {
        _ = try await LLMModelFactory.shared.loadContainer(from: directory, using: MLXModelLoading.tokenizerLoader)
    }
}
