import Foundation

/// Clears the stale partial-file artifacts an interrupted download leaves behind
/// and gives each download generation its own isolated staging.
///
/// Both download stacks resume by appending to an `.incomplete` file. When a
/// transfer dies mid-file the remaining partial can desynchronize with the
/// server (for example a `Range` request answered with the full body), so every
/// later attempt appends to a corrupt file and fails on the same bytes. Removing
/// only the `.incomplete` markers keeps completed files and makes the retry
/// start from a known-good state.
///
/// A transfer that ignores cancellation cannot be forcibly stopped, so before a
/// retry starts the previous generation's cache is *relocated* to a quarantine
/// directory. The abandoned writer keeps writing into the quarantined copy while
/// the retry works in the live path; nothing they touch overlaps.
enum ModelDownloadRecovery {
    struct CleanupResult: Equatable {
        var removedFiles = 0
        var removedBytes: Int64 = 0

        var isEmpty: Bool { removedFiles == 0 }
    }

    struct RelocatedRoot: Equatable {
        let original: URL
        let quarantined: URL
    }

    struct RelocatedFile: Equatable {
        let original: URL
        let quarantined: URL
        let originalRoot: URL
    }

    struct RelocationResult: Equatable {
        var movedRoots: [RelocatedRoot] = []
        var movedFiles: [RelocatedFile] = []
        var quarantineURL: URL?

        var movedDirectories: Int { movedRoots.count }
        var isEmpty: Bool { movedRoots.isEmpty && movedFiles.isEmpty }
    }

    /// Subdirectory that holds relocated generations, kept inside the model
    /// storage root so a single "reset storage" still clears it.
    static let quarantineDirectoryName = ".utter-quarantine"

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

    /// Moves the previous generation's live cache into quarantine so an
    /// abandoned writer cannot corrupt the retry. The quarantine is cleaned
    /// after that writer returns.
    @discardableResult
    static func beginNewGeneration(kind: ModelDownloadKind, modelID: String) -> RelocationResult {
        relocateStaleGeneration(kind: kind, modelID: modelID)
    }

    @discardableResult
    static func relocateStaleGeneration(kind: ModelDownloadKind, modelID: String) -> RelocationResult {
        let quarantine = ModelStorage.huggingFaceBase
            .appendingPathComponent(quarantineDirectoryName, isDirectory: true)
        let roots = liveArtifactRoots(
            kind: kind,
            modelID: modelID,
            storageRoot: ModelStorage.huggingFaceBase,
            cacheRoots: ModelStorage.huggingFaceCacheRoots
        )
        let scopedFiles: [(url: URL, root: URL)]
        if kind == .whisper {
            let repository = ModelStorage.huggingFaceBase
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
    static func liveArtifactRoots(
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

    /// Materializes the exact roots before a transfer starts. This gives a
    /// cancellation quarantine something concrete to move even when the
    /// network fails before the downloader creates its first file.
    static func ensureLiveArtifactRoots(kind: ModelDownloadKind, modelID: String) {
        for root in liveArtifactRoots(
            kind: kind,
            modelID: modelID,
            storageRoot: ModelStorage.huggingFaceBase,
            cacheRoots: ModelStorage.huggingFaceCacheRoots
        ) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    static let whisperRepositoryRelativePath = "models/argmaxinc/whisperkit-coreml"

    /// The variant directory plus the `.cache` tree that stores its partials.
    /// Matching is done on the first path component after the repository root,
    /// so `openai_whisper-large-v3` never matches `openai_whisper-large-v3-turbo`.
    static func whisperVariantRoots(under repository: URL, variant: String) -> [URL] {
        let variantRoot = repository.appendingPathComponent(variant)
        let downloadCache = repository
            .appendingPathComponent(".cache/huggingface/download")
            .appendingPathComponent(variant)
        return [variantRoot, downloadCache]
    }

    /// Exact component match against the repository root, used when filtering a
    /// recursive scan for a single variant.
    static func matchesWhisperVariant(_ url: URL, repository: URL, variant: String) -> Bool {
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
    static func hubCacheRepoName(_ modelID: String) -> String {
        "models--" + modelID.replacingOccurrences(of: "/", with: "--")
    }

    /// Recursively finds `*.incomplete` files. Hidden directories are traversed
    /// because both stacks store partials inside a `.cache` folder.
    static func incompleteFiles(under directory: URL) -> [URL] {
        guard let enumerator = enumerator(at: directory) else { return [] }
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

    /// Moves each existing root into `quarantine`, preserving a readable name.
    static func relocate(_ roots: [URL], into quarantine: URL) -> RelocationResult {
        relocate(roots, files: [], into: quarantine)
    }

    /// Moves exact files that do not live under one of the directory roots into
    /// the same generation quarantine. WhisperKit versions have used both a
    /// variant directory and a flat, variant-prefixed cache layout.
    private static func relocate(
        _ roots: [URL],
        files: [(url: URL, root: URL)],
        into quarantine: URL
    ) -> RelocationResult {
        var result = RelocationResult()
        let generation = quarantine.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for root in roots {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            try? FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
            let baseName = quarantineName(for: root)
            let target = generation.appendingPathComponent(baseName)
            guard (try? FileManager.default.moveItem(at: root, to: target)) != nil else { continue }
            result.movedRoots.append(RelocatedRoot(original: root, quarantined: target))
            result.quarantineURL = generation
        }
        for file in files {
            guard FileManager.default.fileExists(atPath: file.url.path),
                  !result.movedRoots.contains(where: { file.url.path.hasPrefix($0.original.path + "/") }) else {
                continue
            }
            let canonicalFile = file.url.standardizedFileURL.resolvingSymlinksInPath().path
            let canonicalRoot = file.root.standardizedFileURL.resolvingSymlinksInPath().path
            let relative: String
            if canonicalFile.hasPrefix(canonicalRoot + "/") {
                relative = String(canonicalFile.dropFirst(canonicalRoot.count + 1))
            } else {
                relative = file.url.lastPathComponent
            }
            let target = generation.appendingPathComponent("files", isDirectory: true)
                .appendingPathComponent(relative)
            try? FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard (try? FileManager.default.moveItem(at: file.url, to: target)) != nil else { continue }
            result.movedFiles.append(
                RelocatedFile(original: file.url, quarantined: target, originalRoot: file.root)
            )
            result.quarantineURL = generation
        }
        return result
    }

    /// Removes one completed generation's quarantine directory. The directory
    /// is unique per cancellation, so cleaning one generation cannot unlink a
    /// different model's still-running abandoned writer.
    static func clearQuarantine(_ relocation: RelocationResult) {
        guard let quarantine = relocation.quarantineURL else { return }
        for root in relocation.movedRoots {
            restoreCompletedFiles(from: root.quarantined, to: root.original)
        }
        let filesRoot = quarantine.appendingPathComponent("files", isDirectory: true)
        for file in relocation.movedFiles {
            // A downloader may complete a flat-cache file by renaming its
            // `.incomplete` path. Scan the generation's file staging area so
            // that the new final name is restored too; the original path
            // recorded at relocation time no longer exists in that case.
            restoreCompletedFiles(from: filesRoot, to: file.originalRoot)
        }
        try? FileManager.default.removeItem(at: quarantine)
    }

    /// Restores files that the cancelled generation finished before it was
    /// isolated. Partial markers are deliberately left behind in quarantine;
    /// only completed files can be reused by the next generation.
    private static func restoreCompletedFiles(from source: URL, to destination: URL) {
        guard let enumerator = enumerator(at: source) else { return }
        let canonicalSource = source.standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalDestination = destination.standardizedFileURL.resolvingSymlinksInPath()
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension != "incomplete" else { continue }
            let canonicalFile = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
            let relativePath: String
            if canonicalFile.hasPrefix(canonicalSource + "/") {
                relativePath = String(canonicalFile.dropFirst(canonicalSource.count + 1))
            } else {
                relativePath = fileURL.lastPathComponent
            }
            let target = canonicalDestination.appendingPathComponent(relativePath)
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else if !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.moveItem(at: fileURL, to: target)
            }
        }
    }

    private static func quarantineName(for url: URL) -> String {
        url.standardizedFileURL.path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private static func enumerator(at directory: URL) -> FileManager.DirectoryEnumerator? {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )
    }
}
