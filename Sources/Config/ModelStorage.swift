import Foundation
import Hub
import HuggingFace

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

/// A fully materialized candidate and a copy of the currently published
/// model, if one existed. Preparation is deliberately separate from publish:
/// copying model-sized trees may take seconds or minutes and must not occupy
/// the MainActor arbitration point used by Cancel/Delete.
struct PreparedModelGeneration: Sendable {
    let storageRoot: URL
    let candidate: URL
    let destination: URL
    let backup: URL?
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
    static let generationDirectoryName = ".utter-generations"
    static let cleanupDirectoryName = ".utter-cleanup"
    static let promotionDirectoryPrefix = ".utter-promotion-"
    static let backupDirectoryPrefix = ".utter-backup-"

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
            .appendingPathComponent(generationDirectoryName, isDirectory: true)
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
        retireManagedDirectory(at: staging.root, storageRoot: staging.storageRoot)
    }

    /// Removes all managed generation, promotion, backup, and cleanup roots
    /// left by a process that exited before its writer could run its cleanup.
    /// This is a startup-only operation: the ModelCatalog calls it before it
    /// can start a download, so no live writer can own one of these roots.
    /// Runtime cancellation uses the O(1) retirement path below instead of
    /// recursively deleting a model-sized tree on the MainActor.
    @discardableResult
    static func cleanupOrphanedGenerationStaging() -> Int {
        cleanupOrphanedGenerationStaging(storageRoot: huggingFaceBase)
    }

    /// Testable path-scoped implementation used by the startup wrapper.
    @discardableResult
    static func cleanupOrphanedGenerationStaging(storageRoot: URL) -> Int {
        let fileManager = FileManager.default
        var managedDirectories: [URL] = []

        if let enumerator = fileManager.enumerator(
            at: storageRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if name == generationDirectoryName {
                    managedDirectories.append(contentsOf: generationChildren(at: url))
                    enumerator.skipDescendants()
                    continue
                }
                if name == cleanupDirectoryName {
                    managedDirectories.append(contentsOf: cleanupChildren(at: url))
                    enumerator.skipDescendants()
                    continue
                }
                if isManagedTemporaryDirectoryName(name), isDirectory(url) {
                    managedDirectories.append(url)
                    enumerator.skipDescendants()
                }
            }
        }

        var removed = 0
        for directory in managedDirectories.sorted(by: { $0.path.count > $1.path.count }) {
            guard (try? fileManager.removeItem(at: directory)) != nil else { continue }
            removed += 1
        }
        removeEmptyManagedRoot(
            storageRoot.appendingPathComponent(generationDirectoryName, isDirectory: true)
        )
        removeEmptyManagedRoot(
            storageRoot.appendingPathComponent(cleanupDirectoryName, isDirectory: true)
        )
        return removed
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

    /// Materializes a completed staged repository into a candidate and copies
    /// the currently published model into a rollback backup. The expensive
    /// work is safe to run away from the MainActor because neither the staged
    /// tree nor the published tree is modified during preparation.
    static func prepareGenerationCommit(
        kind: ModelDownloadKind,
        modelID: String,
        staging: ModelDownloadStaging
    ) throws -> PreparedModelGeneration {
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
            "\(promotionDirectoryPrefix)\(UUID().uuidString)",
            isDirectory: true
        )
        var backup: URL? = nil
        do {
            var activeSymlinks = Set<String>()
            try materialize(
                from: source,
                to: candidate,
                activeSymlinks: &activeSymlinks
            )

            if fileManager.fileExists(atPath: destination.path) {
                let backupURL = parent.appendingPathComponent(
                    "\(backupDirectoryPrefix)\(UUID().uuidString)",
                    isDirectory: true
                )
                backup = backupURL
                var backupSymlinks = Set<String>()
                try materialize(
                    from: destination,
                    to: backupURL,
                    activeSymlinks: &backupSymlinks
                )
            }
            return PreparedModelGeneration(
                storageRoot: staging.storageRoot,
                candidate: candidate,
                destination: destination,
                backup: backup
            )
        } catch {
            try? fileManager.removeItem(at: candidate)
            if let backup {
                try? fileManager.removeItem(at: backup)
            }
            throw error
        }
    }

    /// Performs preparation on a detached task so the MainActor remains
    /// responsive while large model trees are copied and symlinks resolved.
    static func prepareGenerationCommitOffMainActor(
        kind: ModelDownloadKind,
        modelID: String,
        staging: ModelDownloadStaging
    ) async throws -> PreparedModelGeneration {
        try await Task.detached {
            try prepareGenerationCommit(
                kind: kind,
                modelID: modelID,
                staging: staging
            )
        }.value
    }

    /// Retires an unpublished candidate and any rollback backup. The source
    /// directories are renamed into the managed cleanup root synchronously
    /// and their recursive deletion is detached, so a token rejection never
    /// blocks the MainActor on model-sized I/O.
    static func discardPreparedGeneration(_ prepared: PreparedModelGeneration) {
        retireManagedDirectory(at: prepared.candidate, storageRoot: prepared.storageRoot)
        if let backup = prepared.backup {
            retireManagedDirectory(at: backup, storageRoot: prepared.storageRoot)
        }
    }

    /// Awaits the detached cleanup when a caller needs deterministic cleanup
    /// before returning (for example a focused regression test). Production
    /// download paths use this async form after publication as well.
    static func discardPreparedGenerationOffMainActor(
        _ prepared: PreparedModelGeneration
    ) async {
        await Task.detached {
            removeManagedDirectoryImmediately(at: prepared.candidate)
            if let backup = prepared.backup {
                removeManagedDirectoryImmediately(at: backup)
            }
        }.value
    }

    static func discardPreparedGenerationsOffMainActor(
        _ prepared: [PreparedModelGeneration]
    ) async {
        await Task.detached {
            for generation in prepared {
                removeManagedDirectoryImmediately(at: generation.candidate)
                if let backup = generation.backup {
                    removeManagedDirectoryImmediately(at: backup)
                }
            }
        }.value
    }

    /// Moves a managed directory out of the live model tree without walking
    /// its contents. The detached removal is best effort; a later startup
    /// sweep covers a process that exits before it completes.
    private static func retireManagedDirectory(at url: URL, storageRoot: URL) {
        guard isDirectory(url) else { return }
        let cleanupRoot = storageRoot
            .appendingPathComponent(cleanupDirectoryName, isDirectory: true)
        let retired = cleanupRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: cleanupRoot, withIntermediateDirectories: true)
        if (try? fileManager.moveItem(at: url, to: retired)) == nil {
            Task.detached {
                removeManagedDirectoryImmediately(at: url)
            }
            return
        }
        Task.detached {
            removeManagedDirectoryImmediately(at: retired)
        }
    }

    private static func removeManagedDirectoryImmediately(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && directory.boolValue
    }

    private static func isManagedTemporaryDirectoryName(_ name: String) -> Bool {
        if name.hasPrefix(promotionDirectoryPrefix) {
            return UUID(uuidString: String(name.dropFirst(promotionDirectoryPrefix.count))) != nil
        }
        if name.hasPrefix(backupDirectoryPrefix) {
            return UUID(uuidString: String(name.dropFirst(backupDirectoryPrefix.count))) != nil
        }
        return false
    }

    private static func generationChildren(at root: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        return children.filter { child in
            UUID(uuidString: child.lastPathComponent) != nil && isDirectory(child)
        }
    }

    private static func cleanupChildren(at root: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        return children.filter(isDirectory)
    }

    private static func removeEmptyManagedRoot(_ root: URL) {
        guard isDirectory(root),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: nil,
                  options: []
              ), contents.isEmpty else { return }
        try? FileManager.default.removeItem(at: root)
    }

    /// Commits a prepared generation. Only this short method belongs inside
    /// the MainActor publication critical section. The replacement parameter
    /// is an injectable seam used to force the replacement branch in
    /// regression tests; production calls use the default same-volume
    /// operation.
    static func publishPreparedGeneration(
        _ prepared: PreparedModelGeneration,
        replacement: ((URL, URL) throws -> Void)? = nil
    ) throws {
        let replace = replacement ?? replaceCandidate
        do {
            try replace(prepared.candidate, prepared.destination)
        } catch {
            if let backup = prepared.backup {
                // The replacement may have moved the candidate before
                // reporting an error. Retire that tree in O(1), then restore
                // the complete old model from the same-volume backup.
                retireManagedDirectory(
                    at: prepared.destination,
                    storageRoot: prepared.storageRoot
                )
                try? FileManager.default.moveItem(at: backup, to: prepared.destination)
            } else {
                // There was no previous model to restore; never leave a
                // partially replaced tree behind after a failed operation.
                retireManagedDirectory(
                    at: prepared.destination,
                    storageRoot: prepared.storageRoot
                )
            }
            throw error
        }
    }

    /// Compatibility wrapper for small synchronous callers and existing
    /// tests. Download paths use the detached preparation API above.
    static func commitGeneration(
        kind: ModelDownloadKind,
        modelID: String,
        staging: ModelDownloadStaging
    ) throws {
        let prepared = try prepareGenerationCommit(
            kind: kind,
            modelID: modelID,
            staging: staging
        )
        defer { discardPreparedGeneration(prepared) }
        try publishPreparedGeneration(prepared)
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

    private static func replaceCandidate(_ candidate: URL, _ destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: candidate)
        } else {
            try fileManager.moveItem(at: candidate, to: destination)
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
