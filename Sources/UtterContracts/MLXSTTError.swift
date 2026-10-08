import Foundation

package enum MLXSTTError: LocalizedError {
    case notConfigured
    case noAudioFile
    case modelDirectoryMissing

    package var errorDescription: String? {
        switch self {
        case .notConfigured: return L("error.local_asr_not_configured")
        case .noAudioFile: return L("error.no_audio")
        case .modelDirectoryMissing: return "ASR model directory not found"
        }
    }
}
