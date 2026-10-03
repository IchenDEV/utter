import Foundation
import UtterAppleSpeech
import UtterContracts

extension AppleSpeechEngine {
    convenience init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.init(locale: locale, log: UtterContracts.Log(service: Log.service))
    }
}

extension LegacyAppleSpeechEngine {
    convenience init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.init(locale: locale, log: UtterContracts.Log(service: Log.service))
    }
}

extension AppleSpeechAnalyzer {
    static func transcribe(audioURL: URL, locale: Locale, context: SpeechRecognitionContext = .empty) async throws -> String {
        try await transcribe(audioURL: audioURL, locale: locale, context: context, log: UtterContracts.Log(service: Log.service))
    }
}
