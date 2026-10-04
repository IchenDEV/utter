import UtterContracts
import Foundation

/// Clears the stale partial-file artifacts an interrupted download leaves behind
/// and provides path-scoped recovery seams for tests and future staged clients.
///
/// Both download stacks resume by appending to an `.incomplete` file. When a
/// transfer dies mid-file the remaining partial can desynchronize with the
/// server (for example a `Range` request answered with the full body), so every
/// later attempt appends to a corrupt file and fails on the same bytes. Removing
/// only the `.incomplete` markers keeps completed files and makes the retry
/// start from a known-good state.
///
/// The live coordinator uses token-scoped staging roots for cancellation:
/// pinned Hub dependencies may retain absolute incomplete-file URLs across
/// awaits, but those URLs now point into the retired generation. The relocation
/// helpers below remain useful as explicit path-layout/test seams for legacy
/// recovery, but are not the live writer-isolation mechanism.
package enum ModelDownloadRecovery {
    package struct CleanupResult: Equatable {
        package var removedFiles = 0
        package var removedBytes: Int64 = 0

        package var isEmpty: Bool { removedFiles == 0 }
    }

    package struct RelocatedRoot: Equatable {
        package let original: URL
        package let quarantined: URL
    }

    package struct RelocatedFile: Equatable {
        package let original: URL
        package let quarantined: URL
        package let originalRoot: URL
    }

    package struct RelocationResult: Equatable {
        package var movedRoots: [RelocatedRoot] = []
        package var movedFiles: [RelocatedFile] = []
        package var quarantineURL: URL?

        package var movedDirectories: Int { movedRoots.count }
        package var isEmpty: Bool { movedRoots.isEmpty && movedFiles.isEmpty }
    }

    /// Subdirectory that holds relocated generations, kept inside the model
    /// storage root so a single "reset storage" still clears it.
    package static let quarantineDirectoryName = ".utter-quarantine"

    /// Removes incomplete-download artifacts for `modelID` and reports what was cleared.
    @discardableResult
    package static func purgePartialArtifacts(kind: ModelDownloadKind, modelID: String, storageRoot: URL) -> CleanupResult {
        purge(partialArtifactURLs(kind: kind, modelID: modelID, storageRoot: storageRoot))
    }

    /// Candidate `.incomplete` files for a model across the model storage root
    /// and the shared Hugging Face caches.
    package static func partialArtifactURLs(kind: ModelDownloadKind, modelID: String, storageRoot: URL) -> [URL] {
        incompleteArtifactURLs(
            kind: kind,
            modelID: modelID,
            storageRoot: storageRoot,
            cacheRoots: ModelStorage.huggingFaceCacheRoots
        )
    }

    /// Path-computation seam so the layout can be tested without touching the
    /// user's live model directories.
    package static func incompleteArtifactURLs(
        kind: ModelDownloadKind,
        modelID: String,
        storageRoot: URL,
        cacheRoots: [URL]
    ) -> [URL] {
        switch kind {
        case .whisper:
            let repository = storageRoot.appendingPathComponent(whisperRepositoryRelativePath)
            return incompleteFiles(under: repository).filter {
                matchesWhisperVariant($0, repository: repository, variant: modelID)
            }
        case .llm, .asr:
            return liveArtifactRoots(
                kind: kind,
                modelID: modelID,
                storageRoot: storageRoot,
                cacheRoots: cacheRoots
            ).flatMap { incompleteFiles(under: $0) }
        }
    }

    /// Legacy path-layout helper for callers that need to quarantine existing
    /// live artifacts. Normal cancellation now creates a fresh
    /// `ModelDownloadStaging` root instead of relocating a live directory.
    @discardableResult
    package static func beginNewGeneration(kind: ModelDownloadKind, modelID: String, storageRoot: URL) -> RelocationResult {
        relocateStaleGeneration(kind: kind, modelID: modelID, storageRoot: storageRoot)
    }

    @discardableResult
    package static func relocateStaleGeneration(kind: ModelDownloadKind, modelID: String, storageRoot: URL) -> RelocationResult {
        let quarantine = storageRoot
            .appendingPathComponent(quarantineDirectoryName, isDirectory: true)
        let roots = liveArtifactRoots(
            kind: kind,
            modelID: modelID,
            storageRoot: storageRoot,
            cacheRoots: ModelStorage.huggingFaceCacheRoots
        )
        let scopedFiles: [(url: URL, root: URL)]
        if kind == .whisper {
            let repository = storageRoot
                .appendingPathComponent(whisperRepositoryRelativePath)
            scopedFiles = incompleteFiles(under: repository)
                .filter { matchesWhisperVariant($0, repository: repository, variant: modelID) }
                .map { (url: $0, root: repository) }
        } else {
            scopedFiles = []
        }
        return relocate(roots, files: scopedFiles, into: quarantine)
    }

    /// Directories a model's transfer writes into: the materialized repository
    /// and the per-repository entry in each shared Hugging Face cache.
    package static func liveArtifactRoots(
        kind: ModelDownloadKind,
        modelID: String,
        storageRoot: URL,
        cacheRoots: [URL]
    ) -> [URL] {
        switch kind {
        case .whisper:
            // Every Whisper variant shares one repository and the downloader
            // writes partials under `<variant>/…`. A retry must only consider
            // paths whose first component after the repository root is exactly
            // this variant, never a prefix-sibling such as `large-v3-turbo`
            // when the target is `large-v3`.
            let repo = storageRoot.appendingPathComponent(whisperRepositoryRelativePath)
            return whisperVariantRoots(under: repo, variant: modelID)
        case .llm, .asr:
            let repositoryName = hubCacheRepoName(modelID)
            var roots = [
                storageRoot
                    .appendingPathComponent("models")
                    .appendingPathComponent(modelID),
            ]
            roots.append(contentsOf: cacheRoots.map { $0.appendingPathComponent(repositoryName) })
            return roots
        }
    }

    /// Materializes the exact roots before a transfer starts so status and
    /// partial-file scans observe the same model-scoped layout even when the
    /// network fails before the downloader creates its first file.
    package static func ensureLiveArtifactRoots(kind: ModelDownloadKind, modelID: String, storageRoot: URL) {
        for root in liveArtifactRoots(
            kind: kind,
            modelID: modelID,
            storageRoot: storageRoot,
            cacheRoots: ModelStorage.huggingFaceCacheRoots
        ) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    package static let whisperRepositoryRelativePath = "models/argmaxinc/whisperkit-coreml"

    /// The variant directory plus the `.cache` tree that stores its partials.
    /// Matching is done on the first path component after the repository root,
    /// so `openai_whisper-large-v3` never matches `openai_whisper-large-v3-turbo`.
    package static func whisperVariantRoots(under repository: URL, variant: String) -> [URL] {
        let variantRoot = repository.appendingPathComponent(variant)
        let downloadCache = repository
            .appendingPathComponent(".cache/huggingface/download")
            .appendingPathComponent(variant)
        return [variantRoot, downloadCache]
    }

    /// Exact component match against the repository root, used when filtering a
    /// recursive scan for a single variant.
    package static func matchesWhisperVariant(_ url: URL, repository: URL, variant: String) -> Bool {
        let repoComponents = repository.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let urlComponents = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard urlComponents.count > repoComponents.count,
              Array(urlComponents.prefix(repoComponents.count)) == repoComponents else {
            return false
        }
        let relative = Array(urlComponents.dropFirst(repoComponents.count))

        if let cacheIndex = relative.firstIndex(of: ".cache"),
           relative.count > cacheIndex + 3,
           relative[cacheIndex + 1] == "huggingface",
           relative[cacheIndex + 2] == "download" {
            let downloadRelative = Array(relative.dropFirst(cacheIndex + 3))
            guard let first = downloadRelative.first else { return false }
            return first == variant
                || first.hasPrefix(variant + "_")
                || first.hasPrefix(variant + ".")
        }
        return relative.first == variant
    }

    /// Python-compatible Hugging Face cache folder name, e.g.
    /// `models--mlx-community--Qwen3-ASR-1.7B-bf16`.
}
