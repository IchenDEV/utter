import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterModels
import UtterPresentationContracts

@MainActor
final class Edge0DownloadTests: XCTestCase {
    func testModelScopeDownloadURLsEncodeRepositoryPaths() throws {
        let url = ModelScopeDownloads.fileURL(
            modelID: "Edge0/Edge0-8B-A1B-preview",
            revision: "master",
            path: "sub dir/config.json"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "Revision" })?.value, "master")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "FilePath" })?.value,
            "sub dir/config.json"
        )
        XCTAssertTrue(url.absoluteString.contains("sub%20dir/config.json"))
    }

    func testLiveModelScopeCatalogDownloadOfSmallAssets() async throws {        guard ProcessInfo.processInfo.environment["OPENTYPE_EDGE0_LIVE_DOWNLOAD"] == "1" else {
            throw XCTSkip("Set OPENTYPE_EDGE0_LIVE_DOWNLOAD=1 to download the small Edge0 catalog probe")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-edge0-download-\(UUID().uuidString)")
        let suite = "Edge0Download-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(root.path, forKey: "modelStoragePath")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }

        let artifact = ModelArtifact(
            id: Edge0Model.defaultID,
            kind: .llm,
            displayName: "Edge0 8B-A1B",
            hint: "probe",
            family: .edge0,
            requiredFiles: ["config.json", "tokenizer_config.json"],
            revision: Edge0Model.revision,
            downloadsOnlyRequiredFiles: true,
            runtime: .edge0,
            repositoryHost: .modelScope
        )
        let settings = AppSettings(service: SettingsStore(defaults: defaults))
        let catalog = ModelCatalog(
            settings: settings,
            log: Log(service: TestDiagnostics.service),
            access: LocalModelAccessGate(),
            textDownloads: TextModelDownloadOperations(
                download: { _, _, _, _ in },
                validate: { _ in },
                downloadModelScope: { id, files, revision, staging, progress in
                    try await ModelScopeDownloads.download(
                        modelID: id,
                        revision: revision,
                        files: files,
                        to: ModelStorage.hubModelRepoDir(id, downloadBase: staging.downloadBase),
                        progress: progress
                    )
                },
                validateRequiredFiles: { directory, files in
                    guard ModelAssets.filesAreComplete(at: directory, requiredFiles: files) else {
                        throw ModelScopeError.missingFiles(files)
                    }
                }
            ),
            artifacts: [artifact],
            startupStorageRoot: root,
            startupCleanup: { _ in Task { 0 } }
        )

        await catalog.downloadLLM(Edge0Model.defaultID)
        let index = try XCTUnwrap(catalog.llmModels.firstIndex(where: { $0.id == Edge0Model.defaultID }))
        XCTAssertEqual(catalog.llmModels[index].status, CatalogModelStatus.downloaded)
        let directory = try XCTUnwrap(catalog.llmRepoDir(Edge0Model.defaultID))
        XCTAssertGreaterThan(
            (try? directory.appendingPathComponent("config.json").resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize) ?? 0,
            0
        )
        XCTAssertGreaterThan(
            (try? directory.appendingPathComponent("tokenizer_config.json").resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize) ?? 0,
            0
        )

        let restarted = ModelCatalog(
            settings: settings,
            log: Log(service: TestDiagnostics.service),
            access: LocalModelAccessGate(),
            textDownloads: TextModelDownloadOperations(download: { _, _, _, _ in }, validate: { _ in }),
            artifacts: [artifact],
            startupStorageRoot: root,
            startupCleanup: { _ in Task { 0 } }
        )
        restarted.refreshStatus(recheckingErrors: true)
        XCTAssertEqual(
            restarted.llmModels.first(where: { $0.id == Edge0Model.defaultID })?.status,
            CatalogModelStatus.downloaded
        )

        await restarted.deleteLLM(Edge0Model.defaultID)
        XCTAssertEqual(
            restarted.llmModels.first(where: { $0.id == Edge0Model.defaultID })?.status,
            CatalogModelStatus.notDownloaded
        )
        XCTAssertNil(restarted.llmRepoDir(Edge0Model.defaultID))
    }

    func testFullEdge0DownloadThroughModelScope() async throws {
        guard ProcessInfo.processInfo.environment["OPENTYPE_EDGE0_FULL_DOWNLOAD"] == "1" else {
            throw XCTSkip("Set OPENTYPE_EDGE0_FULL_DOWNLOAD=1 to download the full Edge0 8B checkpoint")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("utter-edge0-full-\(UUID().uuidString)")
        let suite = "Edge0FullDownload-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(root.path, forKey: "modelStoragePath")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }

        let artifact = try XCTUnwrap(Edge0ModelArtifacts.models.first)
        let settings = AppSettings(service: SettingsStore(defaults: defaults))
        let catalog = ModelCatalog(
            settings: settings,
            log: Log(service: TestDiagnostics.service),
            access: LocalModelAccessGate(),
            textDownloads: TextModelDownloadOperations(
                download: { _, _, _, _ in },
                validate: { _ in },
                downloadModelScope: { id, files, revision, staging, progress in
                    try await ModelScopeDownloads.download(
                        modelID: id,
                        revision: revision,
                        files: files,
                        to: ModelStorage.hubModelRepoDir(id, downloadBase: staging.downloadBase),
                        progress: progress
                    )
                },
                validateRequiredFiles: { directory, files in
                    guard ModelAssets.filesAreComplete(at: directory, requiredFiles: files) else {
                        throw ModelScopeError.missingFiles(files)
                    }
                }
            ),
            artifacts: [artifact],
            startupStorageRoot: root,
            startupCleanup: { _ in Task { 0 } }
        )

        await catalog.downloadLLM(Edge0Model.defaultID)
        let index = try XCTUnwrap(catalog.llmModels.firstIndex(where: { $0.id == Edge0Model.defaultID }))
        XCTAssertEqual(catalog.llmModels[index].status, CatalogModelStatus.downloaded)
        let directory = try XCTUnwrap(catalog.llmRepoDir(Edge0Model.defaultID))
        XCTAssertTrue(ModelAssets.filesAreComplete(at: directory, requiredFiles: artifact.requiredFiles))
        XCTAssertGreaterThanOrEqual(catalog.llmModels[index].cacheSize, Edge0Model.downloadBytes)
        await catalog.deleteLLM(Edge0Model.defaultID)
        XCTAssertNil(catalog.llmRepoDir(Edge0Model.defaultID))
    }
}
