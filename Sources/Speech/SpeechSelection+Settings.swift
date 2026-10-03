import Foundation
import UtterContracts
import UtterPresentationContracts

extension SpeechSelection {
    @MainActor
    init(settings: AppSettings, inputLanguage: InputLanguage? = nil) {
        let values = settings.snapshot
        let path = values.speechEngine == .qwen3
            ? ModelCatalog.shared.asrModelPath(for: values.qwenASRModel) : ""
        self.init(settings: values, modelPath: path, inputLanguage: inputLanguage)
    }
}
