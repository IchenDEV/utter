import UtterMediaContracts
import UtterPresentationContracts
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

// Construction bridge retained while native consumers move to injected services.
enum TestDiagnostics {
    static let service: any DiagnosticsService = SystemDiagnostics()
    static func info(_ message: String) { service.info(message) }
    static func sensitive(_ message: String) { service.sensitive(message) }
    static func error(_ message: String) { service.error(message) }
}
