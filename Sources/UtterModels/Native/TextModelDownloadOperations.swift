import Foundation

@MainActor
package struct TextModelDownloadOperations {
    package let download: (String, ModelDownloadStaging, @escaping @Sendable (Progress) -> Void) async throws -> Void
    package let validate: (URL) async throws -> Void
    package init(
        download: @escaping (String, ModelDownloadStaging, @escaping @Sendable (Progress) -> Void) async throws -> Void,
        validate: @escaping (URL) async throws -> Void
    ) {
        self.download = download
        self.validate = validate
    }
}
