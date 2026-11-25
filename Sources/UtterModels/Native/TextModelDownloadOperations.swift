import Foundation
import UtterContracts

package struct TextModelDownloadOperations {
    package let download: (String, ModelDownloadSource, ModelDownloadStaging, @escaping @Sendable (Progress) -> Void) async throws -> Void
    package let validate: (URL) async throws -> Void
    package let downloadModelScope: ((String, [String], String, ModelDownloadStaging, @escaping @Sendable (Progress) -> Void) async throws -> Void)?
    package let validateRequiredFiles: ((URL, [String]) throws -> Void)?

    package init(
        download: @escaping (String, ModelDownloadSource, ModelDownloadStaging, @escaping @Sendable (Progress) -> Void) async throws -> Void,
        validate: @escaping (URL) async throws -> Void,
        downloadModelScope: ((String, [String], String, ModelDownloadStaging, @escaping @Sendable (Progress) -> Void) async throws -> Void)? = nil,
        validateRequiredFiles: ((URL, [String]) throws -> Void)? = nil
    ) {
        self.download = download
        self.validate = validate
        self.downloadModelScope = downloadModelScope
        self.validateRequiredFiles = validateRequiredFiles
    }
}
