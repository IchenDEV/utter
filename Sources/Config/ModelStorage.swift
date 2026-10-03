import UtterModels
import UtterPresentationContracts
import UtterContracts
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

enum ModelStorage {
    static let generationDirectoryName = ModelGenerations.generationDirectoryName
    static let cleanupDirectoryName = ModelGenerations.cleanupDirectoryName

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
        ModelGenerations.retireManagedDirectory(at: staging.root, storageRoot: staging.storageRoot)
    }

    /// Removes all managed generation, promotion, backup, and cleanup roots
    /// left by a process that exited before its writer could run its cleanup.
    /// This synchronous form is kept for non-actor callers and deterministic
    /// path-scoped tests. ModelCatalog startup uses the background entry point
    /// below so recursive removal never occupies the MainActor.
    @discardableResult
    static func cleanupOrphanedGenerationStaging() -> Int {
        cleanupOrphanedGenerationStaging(storageRoot: huggingFaceBase)
    }

    /// Starts the startup sweep away from the MainActor. The returned task is
    /// retained by ModelCatalog and awaited before a new download generation
    /// is admitted, so a fresh writer cannot race orphan reclamation.
    static func cleanupOrphanedGenerationStagingInBackground() -> Task<Int, Never> {
        cleanupOrphanedGenerationStagingInBackground(storageRoot: huggingFaceBase)
    }

    /// Path-scoped background seam used by the responsiveness regression test.
    static func cleanupOrphanedGenerationStagingInBackground(storageRoot: URL, onEnter: (@Sendable () -> Void)? = nil, onExit: (@Sendable () -> Void)? = nil) -> Task<Int, Never> {
        ModelGenerations.cleanupOrphanedGenerationStagingInBackground(storageRoot: storageRoot, onEnter: onEnter, onExit: onExit)
    }

    /// Testable path-scoped implementation used by the startup wrapper.
    @discardableResult
    static func cleanupOrphanedGenerationStaging(storageRoot: URL) -> Int {
        ModelGenerations.cleanupOrphanedGenerationStaging(storageRoot: storageRoot)
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
    static func prepareGenerationCommit(kind: ModelDownloadKind, modelID: String, staging: ModelDownloadStaging) throws -> PreparedModelGeneration {
        let source = kind == .whisper
            ? whisperVariantDir(modelID, downloadBase: staging.downloadBase)
            : hubModelRepoDir(modelID, downloadBase: staging.downloadBase)
        let destination = kind == .whisper
            ? whisperVariantDir(modelID, downloadBase: staging.storageRoot)
            : hubModelRepoDir(modelID, downloadBase: staging.storageRoot)
        return try ModelGenerations.prepare(source: source, destination: destination, storageRoot: staging.storageRoot)
    }

    /// Performs preparation on a detached task so the MainActor remains
    /// responsive while large model trees are copied and symlinks resolved.
    static func prepareGenerationCommitOffMainActor(kind: ModelDownloadKind, modelID: String, staging: ModelDownloadStaging) async throws -> PreparedModelGeneration {
        let source = kind == .whisper
            ? whisperVariantDir(modelID, downloadBase: staging.downloadBase)
            : hubModelRepoDir(modelID, downloadBase: staging.downloadBase)
        let destination = kind == .whisper
            ? whisperVariantDir(modelID, downloadBase: staging.storageRoot)
            : hubModelRepoDir(modelID, downloadBase: staging.storageRoot)
        return try await ModelGenerations.prepareOffMainActor(source: source, destination: destination, storageRoot: staging.storageRoot)
    }

    /// Retires an unpublished candidate and any rollback backup. The source
    /// directories are renamed into the managed cleanup root synchronously
    /// and their recursive deletion is detached, so a token rejection never
    /// blocks the MainActor on model-sized I/O.
    static func discardPreparedGeneration(_ prepared: PreparedModelGeneration) {
        ModelGenerations.discardPreparedGeneration(prepared)
    }

    /// Awaits the detached cleanup when a caller needs deterministic cleanup
    /// before returning (for example a focused regression test). Production
    /// download paths use this async form after publication as well.
    static func discardPreparedGenerationOffMainActor(_ prepared: PreparedModelGeneration) async {
        await ModelGenerations.discardPreparedGenerationOffMainActor(prepared)
    }

    static func discardPreparedGenerationsOffMainActor(_ prepared: [PreparedModelGeneration]) async {
        await ModelGenerations.discardPreparedGenerationsOffMainActor(prepared)
    }

    /// Moves a managed directory out of the live model tree without walking
    /// its contents. The detached removal is best effort; a later startup
    /// sweep covers a process that exits before it completes.







    /// Commits a prepared generation. Only this short method belongs inside
    /// the MainActor publication critical section. The replacement parameter
    /// is an injectable seam used to force the replacement branch in
    /// regression tests; production calls use the default same-volume
    /// operation.
    static func publishPreparedGeneration(_ prepared: PreparedModelGeneration, replacement: ((URL, URL) throws -> Void)? = nil) throws {
        try ModelGenerations.publishPreparedGeneration(prepared, replacement: replacement)
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



    static func localWhisperURL(_ id: String) -> URL? {
        guard let path = AppSettings.shared.localWhisperModelPaths[id] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static func localLLMURL(_ id: String) -> URL? {
        guard let path = AppSettings.shared.localLLMModelPaths[id] else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static func whisperModelIsComplete(at directory: URL) -> Bool { ModelAssets.whisperModelIsComplete(at: directory) }
    static func llmRepoIsComplete(at directory: URL) -> Bool { ModelAssets.llmRepoIsComplete(at: directory) }
    static func directorySize(at directory: URL) -> Int64 { ModelAssets.directorySize(at: directory) }
    static func makeLocalID(prefix: String, folderName: String, existing: Set<String>) -> String {
        ModelAssets.makeLocalID(prefix: prefix, folderName: folderName, existing: existing)
    }
}
