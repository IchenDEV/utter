import Foundation
import UtterRuntime

package protocol ModelResourceAccess: Sendable {
    func withAccess<Value>(_ operation: () async throws -> Value) async throws -> Value
    /// Queue-launched inference shares the current lease and drains before its owner releases access.
    func inheritingCurrentAccess() -> any ModelResourceAccess
}

extension ModelResourceAccess {
    package func inheritingCurrentAccess() -> any ModelResourceAccess { self }
}

package enum ModelResourceError: Error, Equatable {
    case closed
}

package protocol ModelFilesService: Sendable {
    func installedTextModelURL(_ id: String) -> URL?
    func installedSpeechModelURL(_ id: String) -> URL?
    func speechRequiredFiles(_ id: String) -> [String]
    func textModelIsComplete(at url: URL) -> Bool
    func installedWhisperURL(_ id: String) -> URL?
    func whisperVariantURL(_ id: String) -> URL
    func whisperModelIsComplete(at url: URL) -> Bool
}

package enum ModelServices {
    package static let artifacts = ServiceKey<any ModelArtifactService>("models.artifacts")
    package static let catalog = ServiceKey<any ModelCatalogService>("models.catalog")
    package static let textDownloads = ServiceKey<any TextModelDownloadService>("models.text-downloads")
    package static let resourceAccess = ServiceKey<any ModelResourceAccess>("models.resource-access")
    package static let files = ServiceKey<any ModelFilesService>("models.files")
}
