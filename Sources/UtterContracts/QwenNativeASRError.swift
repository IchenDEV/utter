import Foundation

package enum QwenNativeASRError: LocalizedError {
    case notConfigured
    case noAudioFile

    package var errorDescription: String? {
        switch self {
        case .notConfigured: return L("error.local_asr_not_configured")
        case .noAudioFile: return L("error.no_audio")
        }
    }
}
