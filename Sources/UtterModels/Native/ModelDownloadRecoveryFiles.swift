import Foundation
import UtterContracts

extension ModelDownloadRecovery {
    package static func hubCacheRepoName(_ modelID: String) -> String {
        "models--" + modelID.replacingOccurrences(of: "/", with: "--")
    }

    /// Recursively finds `*.incomplete` files. Hidden directories are traversed
    /// because both stacks store partials inside a `.cache` folder.
    package static func incompleteFiles(under directory: URL) -> [URL] {
        guard let enumerator = enumerator(at: directory) else { return [] }
        var result: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "incomplete" {
            result.append(fileURL)
        }
        return result
    }

    /// Deletes the given files, ignoring ones already gone.
    package static func purge(_ urls: [URL]) -> CleanupResult {
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
    package static func relocate(_ roots: [URL], into quarantine: URL) -> RelocationResult {
        relocate(roots, files: [], into: quarantine)
    }

    /// Moves exact files that do not live under one of the directory roots into
    /// the same generation quarantine. WhisperKit versions have used both a
    /// variant directory and a flat, variant-prefixed cache layout.
    static func relocate(
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
    package static func clearQuarantine(_ relocation: RelocationResult) {
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
    static func restoreCompletedFiles(from source: URL, to destination: URL) {
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

    static func quarantineName(for url: URL) -> String {
        url.standardizedFileURL.path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    static func enumerator(at directory: URL) -> FileManager.DirectoryEnumerator? {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )
    }
}
