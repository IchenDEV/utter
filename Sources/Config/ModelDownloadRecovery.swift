import Foundation

/// Clears the stale partial-file artifacts an interrupted download leaves behind.
///
/// Both download stacks resume by appending to an `.incomplete` file. When a
/// transfer dies mid-file the remaining partial can desynchronize with the
/// server (for example a `Range` request answered with the full body), so every
/// later attempt appends to a corrupt file and fails on the same bytes. Removing
/// only the `.incomplete` markers keeps completed files and makes the retry
/// start from a known-good state.
enum ModelDownloadRecovery {
    struct CleanupResult: Equatable {
        var removedFiles = 0
        var removedBytes: Int64 = 0

        var isEmpty: Bool { removedFiles == 0 }
    }

    /// Removes incomplete-download artifacts for `modelID` and reports what was cleared.
    @discardableResult
    static func purgePartialArtifacts(kind: ModelDownloadKind, modelID: String) -> CleanupResult {
        purge(partialArtifactURLs(kind: kind, modelID: modelID))
    }

    /// Candidate `.incomplete` files for a model across the model storage root
    /// and the shared Hugging Face caches.
    static func partialArtifactURLs(kind: ModelDownloadKind, modelID: String) -> [URL] {
        incompleteArtifactURLs(
            kind: kind,
            modelID: modelID,
            storageRoot: ModelStorage.huggingFaceBase,
            cacheRoots: ModelStorage.huggingFaceCacheRoots
        )
    }

    /// Path-computation seam so the layout can be tested without touching the
    /// user's live model directories.
    static func incompleteArtifactURLs(
        kind: ModelDownloadKind,
        modelID: String,
        storageRoot: URL,
        cacheRoots: [URL]
    ) -> [URL] {
        switch kind {
        case .whisper:
            let whisperRepo = storageRoot
                .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            return incompleteFiles(under: whisperRepo)
        case .llm, .asr:
            let repositoryName = hubCacheRepoName(modelID)
            var roots = [
                storageRoot.appendingPathComponent("models").appendingPathComponent(modelID),
            ]
            roots.append(contentsOf: cacheRoots.map { $0.appendingPathComponent(repositoryName) })
            return roots.flatMap { incompleteFiles(under: $0) }
        }
    }

    /// Python-compatible Hugging Face cache folder name, e.g.
    /// `models--mlx-community--Qwen3-ASR-1.7B-bf16`.
    static func hubCacheRepoName(_ modelID: String) -> String {
        "models--" + modelID.replacingOccurrences(of: "/", with: "--")
    }

    /// Recursively finds `*.incomplete` files. Hidden directories are traversed
    /// because both stacks store partials inside a `.cache` folder.
    static func incompleteFiles(under directory: URL) -> [URL] {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
                  at: directory,
                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
              ) else { return [] }

        var result: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "incomplete" {
            result.append(fileURL)
        }
        return result
    }

    /// Deletes the given files, ignoring ones already gone.
    static func purge(_ urls: [URL]) -> CleanupResult {
        var result = CleanupResult()
        for url in urls {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            guard (try? FileManager.default.removeItem(at: url)) != nil else { continue }
            result.removedFiles += 1
            result.removedBytes += size
        }
        return result
    }
}
