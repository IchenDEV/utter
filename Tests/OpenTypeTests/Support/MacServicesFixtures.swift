import UtterModels
import UtterProcessing
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import UtterContracts
import UtterData
import UtterMacServices
import UtterMediaContracts
import UtterPresentationContracts

extension HotkeyActivationController {
    convenience init(settings: AppSettings, onStart: @escaping (HotkeyAction) -> Void,
                     onStop: @escaping (HotkeyAction) -> Void) {
        self.init(settings: { settings.snapshot }, onStart: onStart, onStop: onStop)
    }
}

extension HotkeyManager {
    convenience init(settings: AppSettings, onStart: @escaping (HotkeyAction) -> Void,
                     onStop: @escaping (HotkeyAction) -> Void) {
        self.init(settings: { settings.snapshot }, onStart: onStart, onStop: onStop,
                  log: UtterContracts.Log(service: TestDiagnostics.service),
                  markAccessibilityPrompted: { settings.hotkeyAccessibilityPrompted = true })
    }
}

extension SoundPlayer {
    convenience init() { self.init(enabled: { AppSettings.shared.playSounds }) }
}

extension ScreenOCR {
    static func capture(mode: ScreenContextMode, maxLength: Int = 2000) async -> ScreenContextSnapshot {
        await capture(mode: mode, maxLength: maxLength, log: UtterContracts.Log(service: TestDiagnostics.service))
    }
    static func captureAndRecognize(maxLength: Int = 2000) async -> String {
        await captureAndRecognize(maxLength: maxLength, log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}

extension CorrectionCaptureService {
    convenience init() {
        self.init(enabled: { AppSettings.shared.enableCorrectionLearning },
                  classification: BuiltinCorrectionClassification(),
                  learn: { _ = PersonalDictionary.shared.recordLearnedCandidate($0) },
                  updateHistory: { InputHistory.shared.updateUserFinalText(recordID: $0, text: $1) },
                  log: UtterContracts.Log(service: TestDiagnostics.service))
    }
}
