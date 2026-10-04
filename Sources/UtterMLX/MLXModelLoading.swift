import UtterContracts
import Foundation
import Hub
import HuggingFace
import MLXLMCommon
import Tokenizers

package enum MLXModelLoading {
    package static let tokenizerLoader: any MLXLMCommon.TokenizerLoader = TransformersTokenizerLoader()
    package static let offlineDownloader: any MLXLMCommon.Downloader = OfflineModelDownloader()

    package static func configuration(id: String, directory: URL) throws -> ModelConfiguration {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("config.json"))) as? [String: Any]
        let type = (object?["model_type"] as? String ?? "").lowercased()
        let normalized = id.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        let gemma4 = normalized.contains("gemma4") || type.replacingOccurrences(of: "_", with: "").contains("gemma4")
        return ModelConfiguration(directory: directory, tokenizerSource: .directory(directory),
            extraEOSTokens: gemma4 ? ["<turn|>"] : [])
    }

    package static func downloader(downloadBase: URL, cache: HubCache) -> any MLXLMCommon.Downloader {
        HubDownloader(
            hubApi: HubApi(
                downloadBase: downloadBase,
                cache: cache
            )
        )
    }
}

private struct OfflineModelDownloader: MLXLMCommon.Downloader {
    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        throw GenerationServiceError.modelUnavailable
    }
}

private struct HubDownloader: MLXLMCommon.Downloader {
    let hubApi: HubApi

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        try await hubApi.snapshot(
            from: id,
            revision: revision ?? "main",
            matching: patterns
        ) { progress in
            progressHandler(progress)
        }
    }
}

private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return TransformersTokenizerBridge(tokenizer)
    }
}

private struct TransformersTokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
