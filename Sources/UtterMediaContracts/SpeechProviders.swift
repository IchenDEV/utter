import Foundation
import UtterContracts
import UtterRuntime

package struct SpeechProviderRequest {
    package let selection: SpeechSelection
    package let modelFiles: FrozenModelFiles?
    package let progress: (SpeechModelProgress) -> Void
    package init(selection: SpeechSelection, modelFiles: FrozenModelFiles? = nil, progress: @escaping (SpeechModelProgress) -> Void = { _ in }) {
        self.selection = selection
        self.modelFiles = modelFiles
        self.progress = progress
    }
}

package enum SpeechServices {
    package static let providers = ServiceKey<any ProviderCatalog<SpeechProviderRequest, any SpeechEngine>>("speech.providers")
    package static let apple = ServiceKey<ProviderDescriptor>("speech.apple")
    package static let whisper = ServiceKey<ProviderDescriptor>("speech.whisper")
    package static let qwen = ServiceKey<ProviderDescriptor>("speech.qwen")
    package static let firered = ServiceKey<ProviderDescriptor>("speech.firered")
    package static let mega = ServiceKey<ProviderDescriptor>("speech.mega")
    package static let volc = ServiceKey<ProviderDescriptor>("speech.volc")
}
