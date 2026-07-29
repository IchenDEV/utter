import Foundation

enum WhisperError: LocalizedError {
    case modelNotLoaded(String)
    case noAudioFile
    case downloadFailed(String)
    case compileFailed(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded(let detail):
            return String(format: L("error.whisper_not_loaded"), detail)
        case .noAudioFile:
            return L("error.no_audio")
        case .downloadFailed(let detail):
            return String(format: L("error.download_failed"), detail)
        case .compileFailed(let detail):
            return String(format: L("error.compile_failed"), detail)
        case .loadFailed(let detail):
            return String(format: L("error.load_failed"), detail)
        }
    }
}
