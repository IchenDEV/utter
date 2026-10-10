import UtterContracts
import UtterRuntime

@MainActor
package protocol ModeRecipeService: AnyObject {
    func process(_ request: ProcessingRequest) async throws -> ProcessingResult
    func resolveEditCommand(_ request: ProcessingRequest, context: SpokenEditCommandResolutionContext) async throws -> SpokenEditCommandLLMResolution?
    func cleanReplacement(_ text: String, language: InputLanguage) throws -> String
}

extension ModeRecipeService {
    package func resolveEditCommand(_ request: ProcessingRequest, context: SpokenEditCommandResolutionContext) async throws -> SpokenEditCommandLLMResolution? { nil }
    package func cleanReplacement(_ text: String, language: InputLanguage) throws -> String {
        SpokenEditCommandPayloadCleaner.cleanReplacement(text)
    }
}

package enum ModeServices {
    package static let recipes = ServiceKey<any ProviderCatalog<Void, any ModeRecipeService>>("modes.recipes")
    package static let direct = ServiceKey<ProviderDescriptor>("mode.direct")
    package static let formatting = ServiceKey<ProviderDescriptor>("mode.formatting")
    package static let command = ServiceKey<ProviderDescriptor>("mode.command")
    package static let translation = ServiceKey<ProviderDescriptor>("mode.translation")
    package static let edit = ServiceKey<ProviderDescriptor>("mode.edit")
}
