import Foundation
import UtterContracts
import UtterRuntime

package struct SpeechProviderRequest {
    package let selection: SpeechSelection
    package init(selection: SpeechSelection) { self.selection = selection }
}

package enum SpeechServices {
    package static let providers = ServiceKey<any ProviderCatalog<SpeechProviderRequest, any SpeechEngine>>("speech.providers")
    package static let apple = ServiceKey<ProviderDescriptor>("speech.apple")
}
