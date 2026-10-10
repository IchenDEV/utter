import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import UtterAppleSpeech
import UtterContracts

extension AppleSpeechEngine {
    convenience init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.init(locale: locale, log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}

extension LegacyAppleSpeechEngine {
    convenience init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.init(locale: locale, log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}

extension AppleSpeechAnalyzer {
    static func transcribe(audioURL: URL, locale: Locale, context: SpeechRecognitionContext = .empty) async throws -> String {
        try await transcribe(audioURL: audioURL, locale: locale, context: context, log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}
