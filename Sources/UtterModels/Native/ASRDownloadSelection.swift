import UtterContracts

package enum ASRDownloadSelection {
    package static func revision(for artifact: ModelArtifact?) -> String {
        artifact?.revision ?? "main"
    }

    package static func matchingGlobs(for artifact: ModelArtifact?) -> [String] {
        artifact?.downloadsOnlyRequiredFiles == true ? artifact?.requiredFiles ?? [] : []
    }
}
