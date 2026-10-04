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
import Foundation
import UtterContracts
import UtterData
import UtterPresentationContracts

extension PersonalDictionary {
    static let shared = PersonalDictionary(directoryURL: DataLocations.applicationSupport)

    convenience init(directoryURL: URL? = nil) {
        self.init(service: DictionaryStore(directoryURL: directoryURL), lexicons: IndustryLexiconCatalog.shared)
    }
}
