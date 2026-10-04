import UtterMediaContracts
import UtterData
import UtterProcessing
import UtterMacServices
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
import UtterModels
import UtterPresentationContracts

typealias LiveModelFiles = ConfiguredModelFiles

extension ConfiguredModelFiles {
    init() {
        self.init(
            settings: { AppSettings.shared.snapshot },
            speechRequiredFiles: { ModelCatalog.asrRequiredFiles(for: $0) }
        )
    }
}
