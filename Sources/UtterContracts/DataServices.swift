import Foundation
import UtterRuntime

package protocol LexiconService: Sendable {
    var version: String { get }
    var sources: [IndustryLexiconSource] { get }
    var packs: [IndustryLexiconPack] { get }
    func snapshot(for id: IndustryLexiconID) -> IndustryLexiconSnapshot
}

@MainActor
package protocol ConfigurationService: AnyObject {
    var document: CompositionDocument? { get }
    var mounted: EffectiveComposition? { get }
    var pending: EffectiveComposition? { get }
    var restartRequired: Bool { get }
    var sessionSnapshot: EffectiveComposition { get throws }
    func save(_ proposed: CompositionDocument) throws
    func resetToShipped() throws -> URL?
}

package enum DataServices {
    package static let settings = ServiceKey<any SettingsService>("data.settings")
    package static let lexicons = ServiceKey<any LexiconService>("data.lexicons")
    package static let configuration = ServiceKey<any ConfigurationService>("data.configuration")
}
