import UtterMediaContracts
import UtterModels
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
import UtterContracts
import UtterData
import UtterPresentationContracts

@MainActor
extension InputHistory {
    static let shared = InputHistory(service: HistoryStore(
        directoryURL: DataLocations.applicationSupport,
        retention: { AppSettings.shared.historyRetention },
        reportError: TestDiagnostics.error
    ))
}
