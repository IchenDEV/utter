import MLX
import UtterContracts
import CoreGraphics
import CoreImage
import Foundation
import MLXLMCommon
import MLXVLM

package actor VLMEngine {
    private let files: any ModelFilesService
    private var closed = false
    private var modelLoadAttempted = false
    private let log: Log

    package init(files: any ModelFilesService, log: Log) {
        self.files = files
        self.log = log
    }

    private var container: ModelContainer?
    private var currentModelID: String?
    private var currentModelRevision: String?

    package func loadModel(id: String, modelURL: URL? = nil) async throws {
        try Task.checkCancellation()
        guard !closed else { throw GenerationServiceError.unsupportedOperation }

        log.info("[VLMEngine] loading model: \(id)")
        let started = CFAbsoluteTimeGetCurrent()

        guard let localURL = modelURL ?? files.installedTextModelURL(id) else {
            throw LLMError.modelNotDownloaded
        }
        let revision = ModelLocationLease.identity(localURL)
        if currentModelID == id, currentModelRevision == revision, container != nil { return }
        modelLoadAttempted = true
        let loaded = try await VLMModelFactory.shared.loadContainer(
            from: localURL,
            using: MLXModelLoading.tokenizerLoader
        )

        try Task.checkCancellation()
        guard !closed else { throw GenerationServiceError.unsupportedOperation }
        container = loaded
        currentModelID = id
        currentModelRevision = revision
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        log.info("[VLMEngine] model loaded in \(String(format: "%.1f", elapsed))s")
    }

    package func generate(
        prompt: String,
        systemPrompt: String? = nil,
        image: CGImage,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) async throws -> String {
        try Task.checkCancellation()
        guard !closed else { throw GenerationServiceError.unsupportedOperation }
        guard let container else {
            throw LLMError.modelNotLoaded
        }

        let started = CFAbsoluteTimeGetCurrent()
        let params = GenerateParameters(maxTokens: maxTokens, temperature: Float(temperature))
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: params,
            processing: .init()
        )
        let ciImage = CIImage(cgImage: image)
        let result = try await session.respond(to: prompt, image: .ciImage(ciImage))

        let elapsed = CFAbsoluteTimeGetCurrent() - started
        log.info("[VLMEngine] generated \(result.count) chars in \(String(format: "%.1f", elapsed))s")
        return result
    }

    package var isLoaded: Bool { container != nil }

    package func close() {
        closed = true
        unload()
    }

    package func unload() {
        container = nil
        currentModelID = nil
        currentModelRevision = nil
        if modelLoadAttempted {
            modelLoadAttempted = false
            Memory.clearCache()
        }
    }
}
