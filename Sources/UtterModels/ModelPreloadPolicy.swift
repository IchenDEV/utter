import Foundation
import UtterContracts

package enum ModelPreloadPolicy {
    package static func speech(enabled: Bool, engine: SpeechEngineType, installed: Bool) -> Bool {
        enabled && engine == .whisper && installed
    }

    package static func text(enabled: Bool, remote: Bool, modelID: String, installed: Bool) -> Bool {
        enabled && !remote && installed && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
