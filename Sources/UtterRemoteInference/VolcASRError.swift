import Foundation
import UtterContracts

package enum VolcASRError: LocalizedError {
    case notConfigured
    case noAudioFile
    case invalidEndpoint
    case audioConversionFailed
    case timeout
    case handshakeRejected
    case serverError(code: Int, message: String)

    package var errorDescription: String? {
        switch self {
        case .notConfigured:        return L("error.volc_not_configured")
        case .noAudioFile:          return L("error.no_audio")
        case .invalidEndpoint:      return L("error.volc_invalid_endpoint")
        case .audioConversionFailed: return L("error.volc_audio_conversion")
        case .timeout:              return L("error.volc_timeout")
        case .handshakeRejected:    return L("error.volc_handshake_rejected")
        case .serverError(let code, let msg): return "ASR Error \(code): \(msg)"
        }
    }
}
