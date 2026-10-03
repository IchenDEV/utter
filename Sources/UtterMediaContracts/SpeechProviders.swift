import Foundation
import UtterContracts
import UtterRuntime

package struct SpeechProviderRequest {
    package let selection: SpeechSelection
    package let progress: (SpeechModelProgress) -> Void
    package init(selection: SpeechSelection, progress: @escaping (SpeechModelProgress) -> Void = { _ in }) {
        self.selection = selection
        self.progress = progress
    }
}

package enum SpeechServices {
    package static let providers = ServiceKey<any ProviderCatalog<SpeechProviderRequest, any SpeechEngine>>("speech.providers")
    package static let apple = ServiceKey<ProviderDescriptor>("speech.apple")
    package static let whisper = ServiceKey<ProviderDescriptor>("speech.whisper")
}
