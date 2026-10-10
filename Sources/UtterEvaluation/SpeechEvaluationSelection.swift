import Foundation
import UtterContracts

package struct SpeechEvaluationSelection {
    package let providerID: String
    package let type: SpeechEngineType
    package let model: URL
    package let modelID: String
    package init(provider: String, model: URL, modelID: String) throws {
        switch provider {
        case "whisper": type = .whisper
        case "qwen": type = .qwen3
        case "firered": type = .firered
        case "mega": type = .megaASR
        default: throw VoiceEvaluationError.invalidArguments("unsupported offline speech provider: \(provider)")
        }
        providerID = "speech." + provider
        self.model = model.standardizedFileURL.resolvingSymlinksInPath()
        self.modelID = modelID
    }
}
