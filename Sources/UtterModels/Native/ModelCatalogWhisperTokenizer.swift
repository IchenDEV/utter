import Foundation
import Hub
import UtterContracts

@MainActor
extension ModelCatalog {
    func stageExistingWhisper(from source: URL, to destination: URL) async throws {
        try Task.checkCancellation()
        try await Task.detached {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        }.value
        try Task.checkCancellation()
    }

    func installWhisperTokenizer(model: String, directory: URL, staging: ModelDownloadStaging) async throws {
        try Task.checkCancellation()
        if (try? WhisperTokenizerAssets.read(at: directory, expectedModel: model)) != nil { return }
        guard let repository = WhisperTokenizerAssets.repository(for: model)
            ?? WhisperTokenizerAssets.repository(for: directory.lastPathComponent) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let downloaded = try await HubApi(downloadBase: staging.downloadBase, cache: staging.hubCache)
            .snapshot(from: repository, matching: ["tokenizer.json", "tokenizer_config.json"])
        try Task.checkCancellation()
        let destination = directory.appendingPathComponent(WhisperTokenizerAssets.directoryName, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in ["tokenizer.json", "tokenizer_config.json"] {
            try FileManager.default.copyItem(at: downloaded.appendingPathComponent(name), to: destination.appendingPathComponent(name))
        }
        try WhisperTokenizerAssets.writeManifest(repository: repository, at: destination)
        _ = try WhisperTokenizerAssets.read(at: directory, expectedModel: model)
        try Task.checkCancellation()
    }
}
