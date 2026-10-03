import UtterContracts
import UtterPresentationContracts

extension TextProcessingOptions {
    init(settings: AppSettings, inputLanguage: InputLanguage? = nil) {
        self.init(settings: settings.snapshot, inputLanguage: inputLanguage)
    }
}
