import Foundation
import Hub
import MLXLMCommon
import Tokenizers

enum MLXModelLoading {
    static let downloader: any MLXLMCommon.Downloader = HubDownloader(
        hubApi: HubApi(downloadBase: ModelStorage.huggingFaceBase)
    )
    static let tokenizerLoader: any MLXLMCommon.TokenizerLoader = TransformersTokenizerLoader()

    static func downloader(for staging: ModelDownloadStaging) -> any MLXLMCommon.Downloader {
        HubDownloader(
            hubApi: HubApi(
                downloadBase: staging.downloadBase,
                cache: staging.hubCache
            )
        )
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
