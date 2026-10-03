import Foundation
import UtterContracts

struct LiveModelFiles: ModelFilesService {
    func installedTextModelURL(_ id: String) -> URL? { ModelStorage.installedLLMURL(id) }
    func installedSpeechModelURL(_ id: String) -> URL? { ModelStorage.asrRepoDir(id) }
    func speechRequiredFiles(_ id: String) -> [String] { ModelCatalog.asrRequiredFiles(for: id) }
    func textModelIsComplete(at url: URL) -> Bool { ModelStorage.llmRepoIsComplete(at: url) }
    func installedWhisperURL(_ id: String) -> URL? { ModelStorage.localWhisperURL(id) }
    func whisperVariantURL(_ id: String) -> URL { ModelStorage.whisperVariantDir(id) }
    func whisperModelIsComplete(at url: URL) -> Bool { ModelStorage.whisperModelIsComplete(at: url) }
}
