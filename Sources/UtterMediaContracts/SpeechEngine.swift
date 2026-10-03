import UtterContracts
import Foundation
import AVFoundation

package protocol SpeechEngine: AnyObject {
    var isReady: Bool { get }
    var supportsStreaming: Bool { get }
    /// Optional warm-up: load models or start helper processes ahead of the
    /// first transcription. Must be safe to call repeatedly.
    func prepare() async
    func configureRecognition(context: SpeechRecognitionContext)
    func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void)
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func finishListening(audioURL: URL?, language: String?) async throws -> String
    func cancelListening()
    func transcribe(audioURL: URL?, language: String?) async throws -> String
}

extension SpeechEngine {
    package var supportsStreaming: Bool { false }

    package func prepare() async {}

    package func configureRecognition(context: SpeechRecognitionContext) {
        let _ = context
    }

    package func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        let _ = language
        let _ = onPartialResult
    }

    package func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let _ = buffer
    }

    package func finishListening(audioURL: URL?, language: String?) async throws -> String {
        try await transcribe(audioURL: audioURL, language: language)
    }

    package func cancelListening() {}
}
