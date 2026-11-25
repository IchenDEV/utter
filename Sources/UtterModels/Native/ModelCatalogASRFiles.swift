import UtterContracts
import Foundation

package enum ASRModelRevisionMarker {
    package static let filename = ".utter-model-revision"

    package static func write(revision: String, to directory: URL) throws {
        try Data((revision + "\n").utf8).write(
            to: directory.appendingPathComponent(filename),
            options: .atomic
        )
    }

    package static func matches(revision: String?, at directory: URL?) -> Bool {
        guard let revision else { return true }
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(filename)),
              let stored = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return stored == revision
    }
}

extension ModelCatalog {
    func asrRepoContainsRequiredFiles(_ id: String, at directory: URL?) -> Bool {
        guard let artifact = artifactsByID[id] else { return false }
        return ModelAssets.speechModelIsComplete(at: directory, requiredFiles: artifact.requiredFiles)
            && ASRModelRevisionMarker.matches(revision: artifact.revision, at: directory)
    }
}
