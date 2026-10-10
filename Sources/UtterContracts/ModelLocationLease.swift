import Foundation

package struct ModelLocationLease: Equatable, Sendable {
    package let url: URL?
    package let revision: String

    package init(_ url: URL?) {
        self.url = url
        revision = Self.identity(url)
    }

    package var isCurrent: Bool { revision == Self.identity(url) }

    package func requireInstalledURL() throws -> URL {
        guard let url else { throw GenerationServiceError.modelUnavailable }
        guard isCurrent else { throw GenerationServiceError.modelChanged }
        return url
    }

    package static func identity(_ url: URL?) -> String {
        guard let url else { return "missing" }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return url.path + ":missing" }
        let device = attributes[.systemNumber] as? NSNumber
        let inode = attributes[.systemFileNumber] as? NSNumber
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970
        return url.path + ":" + String(describing: device) + ":" + String(describing: inode)
            + ":" + String(describing: modified)
    }
}

package struct FrozenGenerationVersions: Equatable, Sendable {
    package let bundle: ModelLocationLease
    package let directory: ModelLocationLease
    package init(bundle: URL?, directory: URL?) {
        self.bundle = ModelLocationLease(bundle)
        self.directory = ModelLocationLease(directory)
    }
}
