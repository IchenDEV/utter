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
