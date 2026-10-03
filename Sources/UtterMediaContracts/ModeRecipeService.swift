import UtterContracts
import UtterRuntime

@MainActor
package protocol ModeRecipeService: AnyObject {
    func process(_ request: ProcessingRequest) async throws -> ProcessingResult
}

package enum ModeServices {
    package static let recipes = ServiceKey<any ProviderCatalog<Void, any ModeRecipeService>>("modes.recipes")
    package static let direct = ServiceKey<ProviderDescriptor>("mode.direct")
    package static let formatting = ServiceKey<ProviderDescriptor>("mode.formatting")
    package static let command = ServiceKey<ProviderDescriptor>("mode.command")
    package static let translation = ServiceKey<ProviderDescriptor>("mode.translation")
    package static let edit = ServiceKey<ProviderDescriptor>("mode.edit")
}
