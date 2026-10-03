import Foundation

package enum QwenAudioPreprocessorError: LocalizedError {
    case conversionFailed

    package var errorDescription: String? {
        L("error.local_asr_audio_conversion")
    }
}
