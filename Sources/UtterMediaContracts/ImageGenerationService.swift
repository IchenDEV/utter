import CoreGraphics
import UtterContracts
import UtterRuntime

package struct ImageGenerationRequest {
    package let text: TextGenerationRequest
    package let image: CGImage

    package init(text: TextGenerationRequest, image: CGImage) {
        self.text = text
        self.image = image
    }
}

package protocol ImageGenerationService: Sendable {
    func generate(_ request: ImageGenerationRequest) async throws -> String
    func unload() async
}

package enum ImageGenerationServices {
    package static let providers = ServiceKey<any ProviderCatalog<GenerationPurpose, any ImageGenerationService>>("generation.image-providers")
    package static let mlx = ServiceKey<ProviderDescriptor>("generation.mlx-image")
}
