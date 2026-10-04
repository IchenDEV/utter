import Foundation
import UtterAudio
import UtterContracts
import UtterPresentationContracts

extension AudioCaptureManager {
    convenience init() {
        self.init(log: UtterContracts.Log(service: TestDiagnostics.service), remoteEnabled: { AppSettings.shared.remoteMicEnabled })
    }
}

extension SpeechActivityClassifier {
    static func containsSpeech(at audioURL: URL?) async -> Bool {
        await containsSpeech(at: audioURL, diagnostics: UtterContracts.Log(service: TestDiagnostics.service))
    }
}

extension AudioCaptureDiagnostics {
    static func log(_ activity: AudioCaptureActivity) {
        log(activity, diagnostics: UtterContracts.Log(service: TestDiagnostics.service))
    }
}
