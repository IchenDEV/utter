import Foundation
import Hub

/// All dependency writes for one download generation live below this root.
/// The root is deliberately separate from the published model directory so a
/// cancelled writer can finish (or be abandoned) without touching a newer
/// generation's files.
struct ModelDownloadStaging: Sendable {
    let token: UUID
    let storageRoot: URL
    let root: URL
    let downloadBase: URL
    let hubCache: HubCache
}

enum ModelGenerationError: LocalizedError {
    case missingSource(URL)
    case symlinkCycle(URL)

    var errorDescription: String? {
        switch self {
        case .missingSource(let url):
            return "Staged model output is missing: \(url.path)"
        case .symlinkCycle(let url):
            return "Staged model contains a symbolic-link cycle: \(url.path)"
        }
    }
}

enum ModelStorage {
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(ProductBrand.applicationSupportDirectoryName)
            .appendingPathComponent("huggingface")
    }

    static var root: URL {
        let path = AppSettings.shared.modelStoragePath
        let url = path.isEmpty ? defaultRoot : URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var huggingFaceBase: URL {
        root
    }

    static func generationStaging(for token: UUID) -> ModelDownloadStaging {
        generationStaging(for: token, storageRoot: huggingFaceBase)
    }

    /// Returns paths only. Callers prepare the directories immediately before
    /// starting dependency I/O and remove the root in their operation's
    /// `defer`, which keeps it alive for the entire lifetime of a cancelled
    /// writer.
    static func generationStaging(
        for token: UUID,
        storageRoot: URL
    ) -> ModelDownloadStaging {
        let root = storageRoot
            .appendingPathComponent(".utter-generations", isDirectory: true)
            .appendingPathComponent(token.uuidString, isDirectory: true)
        return ModelDownloadStaging(
            token: token,
            storageRoot: storageRoot,
            root: root,
            downloadBase: root.appendingPathComponent("download", isDirectory: true),
            hubCache: HubCache(
                cacheDirectory: root.appendingPathComponent("hub", isDirectory: true)
            )
        )
    }

    static func prepareGeneration(_ staging: ModelDownloadStaging) throws {
        try FileManager.default.createDirectory(
            at: staging.downloadBase,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: staging.hubCache.cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    static func removeGenerationStaging(_ staging: ModelDownloadStaging) {
        try? FileManager.default.removeItem(at: staging.root)
    }

    static var hubModelsBase: URL {
        huggingFaceBase.appendingPathComponent("models")
    }

    static func whisperVariantDir(_ variant: String) -> URL {
        whisperVariantDir(variant, downloadBase: huggingFaceBase)
    }

    static func whisperVariantDir(_ variant: String, downloadBase: URL) -> URL {
        downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(variant, isDirectory: true)
    }

    /// WhisperKit repository root; it also holds the `.cache` tree where the
    /// CoreML downloader parks `.incomplete` files.
    static var whisperRepoCacheRoot: URL {
        hubModelsBase.appendingPathComponent("argmaxinc/whisperkit-coreml")
    }

    /// Shared Hugging Face hub caches the Swift Hub client may use for blobs.
    /// The client follows `HF_HUB_CACHE` -> `HF_HOME/hub` -> the per-user cache,
    /// which sits outside `root` and survives deleting a materialized model.
    static var huggingFaceCacheRoots: [URL] {
        var roots: [URL] = []
        let environment = ProcessInfo.processInfo.environment
        if let hubCache = environment["HF_HUB_CACHE"], !hubCache.isEmpty {
            roots.append(URL(fileURLWithPath: NSString(string: hubCache).expandingTildeInPath))
        }
        if let hubHome = environment["HF_HOME"], !hubHome.isEmpty {
            roots.append(
                URL(fileURLWithPath: NSString(string: hubHome).expandingTildeInPath)
                    .appendingPathComponent("hub")
            )
        }
        roots.append(
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".cache/huggingface/hub")
        )
        if environment["APP_SANDBOX_CONTAINER_ID"] != nil,
           let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            roots.append(caches.appendingPathComponent("huggingface/hub"))
        }
        return roots
    }

    static func hubModelRepo(_ modelID: String) -> Hub.Repo {
        Hub.Repo(id: modelID, type: .models)
    }

    static func hubModelRepoDir(_ modelID: String) -> URL {
        hubModelRepoDir(modelID, downloadBase: huggingFaceBase)
    }

    static func hubModelRepoDir(_ modelID: String, downloadBase: URL) -> URL {
        HubApi(downloadBase: downloadBase, cache: nil).localRepoLocation(hubModelRepo(modelID))
    }

    static func llmRepoDir(_ modelID: String) -> URL? {
        if let local = localLLMURL(modelID) { return local }
        let dir = hubModelRepoDir(modelID)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    static func installedLLMURL(_ modelID: String) -> URL? {
        guard let dir = llmRepoDir(modelID), llmRepoIsComplete(at: dir) else { return nil }
        return dir
    }

    static func asrRepoDir(_ modelID: String) -> URL? {
        let dir = hubModelRepoDir(modelID)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    static func asrRepoDir(_ modelID: String, downloadBase: URL) -> URL {
        hubModelRepoDir(modelID, downloadBase: downloadBase)
    }

    /// Materializes a completed staged repository into the published location.
    /// Hub snapshots may contain relative symlinks into their blob cache; the
    /// copy is intentionally resolved before the staging root is removed, so
    /// the published model never depends on a deleted generation cache.
    static func commitGeneration(
        kind: ModelDownloadKind,
        modelID: String,
        staging: ModelDownloadStaging
    ) throws {
        let source: URL
        let destination: URL
        switch kind {
        case .whisper:
            source = whisperVariantDir(modelID, downloadBase: staging.downloadBase)
            destination = whisperVariantDir(modelID, downloadBase: staging.storageRoot)
        case .llm, .asr:
            source = hubModelRepoDir(modelID, downloadBase: staging.downloadBase)
            destination = hubModelRepoDir(modelID, downloadBase: staging.storageRoot)
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else {
            throw ModelGenerationError.missingSource(source)
        }

        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let candidate = parent.appendingPathComponent(
            ".utter-promotion-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: candidate) }

        var activeSymlinks = Set<String>()
        try materialize(
            from: source,
            to: candidate,
            activeSymlinks: &activeSymlinks
        )
        try publish(candidate: candidate, destination: destination)
    }

    private static func materialize(
        from source: URL,
        to destination: URL,
        activeSymlinks: inout Set<String>
    ) throws {
        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        if let type = attributes[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            guard activeSymlinks.insert(source.path).inserted else {
                throw ModelGenerationError.symlinkCycle(source)
            }
            defer { activeSymlinks.remove(source.path) }
            let target = try fileManager.destinationOfSymbolicLink(atPath: source.path)
            let resolved = URL(
                fileURLWithPath: target,
                relativeTo: source.deletingLastPathComponent()
            ).standardizedFileURL
            try materialize(
                from: resolved,
                to: destination,
                activeSymlinks: &activeSymlinks
            )
            return
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ModelGenerationError.missingSource(source)
        }
        if isDirectory.boolValue {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let children = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: []
            ).sorted { $0.path < $1.path }
            for child in children {
                try materialize(
                    from: child,
                    to: destination.appendingPathComponent(child.lastPathComponent),
                    activeSymlinks: &activeSymlinks
                )
            }
        } else {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    /// Build the candidate completely before this point. The only operation
    /// touching the published directory is the atomic replacement. A regular
    /// backup is retained until replacement succeeds so a failed commit can
    /// restore the previous model without exposing a partially copied tree.
    private static func publish(candidate: URL, destination: URL) throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let backup = parent.appendingPathComponent(
            ".utter-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        let hasOriginal = fileManager.fileExists(atPath: destination.path)
        var backupReady = false

        do {
            if hasOriginal {
                var activeSymlinks = Set<String>()
                try materialize(
                    from: destination,
                    to: backup,
                    activeSymlinks: &activeSymlinks
                )
                backupReady = true
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: candidate
                )
            } else {
                try fileManager.moveItem(at: candidate, to: destination)
            }
            if hasOriginal {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            if backupReady {
                try? fileManager.removeItem(at: destination)
                try? fileManager.moveItem(at: backup, to: destination)
            } else {
                try? fileManager.removeItem(at: backup)
            }
            throw error
        }
    }

    static func localWhisperURL(_ id: String) -> URL? {
        guard let path = AppSettings.shared.localWhisperModelPaths[id] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static func localLLMURL(_ id: String) -> URL? {
        guard let path = AppSettings.shared.localLLMModelPaths[id] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static func whisperModelIsComplete(at dir: URL) -> Bool {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            resourceHasContent(dir.appendingPathComponent("\(name).mlmodelc")) ||
                resourceHasContent(dir.appendingPathComponent("\(name).mlpackage"))
        }
    }

    static func llmRepoIsComplete(at dir: URL) -> Bool {
        guard fileExists(dir.appendingPathComponent("config.json")) else { return false }
        let indexURL = dir.appendingPathComponent("model.safetensors.index.json")
        if fileExists(indexURL),
           let data = try? Data(contentsOf: indexURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let weightMap = object["weight_map"] as? [String: String] {
            let shards = Set(weightMap.values)
            return !shards.isEmpty && shards.allSatisfy {
                fileExists(dir.appendingPathComponent($0))
            }
        }

        if fileExists(dir.appendingPathComponent("model.safetensors")) ||
            fileExists(dir.appendingPathComponent("weights.safetensors")) {
            return true
        }

        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "npz",
               fileExists(fileURL) {
                return true
            }
        }
        return false
    }

    static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let sz = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(sz)
            }
        }
        return total
    }

    private static func fileExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0 > 0
    }

    private static func resourceHasContent(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue ? directorySize(at: url) > 0 : fileExists(url)
    }

    static func makeLocalID(prefix: String, folderName: String, existing: Set<String>) -> String {
        let cleanName = folderName.isEmpty ? "model" : folderName
        let base = "local/\(prefix)-\(cleanName)"
        guard existing.contains(base) else { return base }
        for n in 2...999 {
            let candidate = "\(base)-\(n)"
            if !existing.contains(candidate) { return candidate }
        }
        return "\(base)-\(UUID().uuidString.prefix(8))"
    }
}
