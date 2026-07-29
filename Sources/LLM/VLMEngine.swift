import CoreGraphics
import CoreImage
import Foundation
import MLXLMCommon
import MLXVLM

actor VLMEngine {
    private var container: ModelContainer?
    private var currentModelID: String?

    func loadModel(id: String) async throws {
        if currentModelID == id, container != nil { return }

        Log.info("[VLMEngine] loading model: \(id)")
        let started = CFAbsoluteTimeGetCurrent()

        guard let localURL = ModelStorage.installedLLMURL(id) else {
            throw LLMError.modelNotDownloaded
        }
        container = try await VLMModelFactory.shared.loadContainer(
            from: localURL,
            using: MLXModelLoading.tokenizerLoader
        )

        currentModelID = id
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info("[VLMEngine] model loaded in \(String(format: "%.1f", elapsed))s")
    }

    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        image: CGImage,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) async throws -> String {
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
        Log.info("[VLMEngine] generated \(result.count) chars in \(String(format: "%.1f", elapsed))s")
        return result
    }

    var isLoaded: Bool { container != nil }

    func unload() {
        container = nil
        currentModelID = nil
    }
}
