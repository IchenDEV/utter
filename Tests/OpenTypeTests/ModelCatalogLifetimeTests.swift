import Foundation
import XCTest
import UtterContracts
import UtterData
import UtterPresentationContracts
@testable import UtterModels
import UtterMLX

@MainActor
final class ModelCatalogLifetimeTests: XCTestCase {
    func testColdCatalogDoesNotRepairPreferencesOrStartCleanup() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        var calls = 0
        let before = fixture.settings.snapshot
        let catalog = fixture.catalog(cleanup: { _ in calls += 1; return Task { 0 } })
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(fixture.settings.snapshot, before)
        catalog.start()
        catalog.start()
        XCTAssertEqual(calls, 1)
        await catalog.close()
        catalog.start()
        XCTAssertEqual(calls, 1)
    }

    func testCloseWaitsForAdmittedCleanupAndRejectsPreferenceMutation() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let gate = CatalogLifetimeGate()
        let catalog = fixture.catalog(cleanup: { _ in Task { await gate.wait(); return 0 } })
        catalog.start()
        await gate.waitUntilEntered()
        var closed = false
        let close = Task { await catalog.close(); closed = true }
        while !catalog.closed { await Task.yield() }
        let preferences = fixture.settings.snapshot
        catalog.addCustomLLM("late-provider/model")
        await catalog.downloadLLM("late-provider/model")
        XCTAssertEqual(fixture.settings.snapshot, preferences)
        XCTAssertFalse(closed)
        await gate.release()
        await close.value
        XCTAssertTrue(closed)
    }

    func testModelMaintenanceWaitsForAnActiveResourceLease() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let gate = CatalogLifetimeGate()
        let access = LocalModelAccessGate()
        let catalog = fixture.catalog(access: access)
        let user = Task { try await access.withAccess { await gate.wait() } }
        await gate.waitUntilEntered()
        var removed = false
        let maintenance = Task { await catalog.removeFiles { removed = true } }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(removed)
        await gate.release()
        _ = try await user.value
        await maintenance.value
        XCTAssertTrue(removed)
        await catalog.close()
        await access.close()
    }
    func testDeleteRetainsItsAdmittedPathWhenStorageChangesWhileWaiting() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let newerRoot = fixture.root.appendingPathComponent("new-root")
        let id = "test-frozen-delete"
        let original = ModelStorage.whisperVariantDir(id, downloadBase: fixture.root)
        let newer = ModelStorage.whisperVariantDir(id, downloadBase: newerRoot)
        for directory in [original, newer] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1]).write(to: directory.appendingPathComponent("marker"))
        }
        let access = LocalModelAccessGate()
        let gate = CatalogLifetimeGate()
        let catalog = fixture.catalog(access: access)
        catalog.whisperModels.append(CatalogModelEntry(id: id, displayName: id, hint: "", family: nil))
        let user = Task { try await access.withAccess { await gate.wait() } }
        await gate.waitUntilEntered()
        let deletion = Task { await catalog.deleteWhisper(id) }
        while !catalog.downloadTasks.isActive(ModelDownloadKey(kind: .whisper, modelID: id)) { await Task.yield() }
        fixture.settings.modelStoragePath = newerRoot.path
        await gate.release()
        _ = try await user.value
        await deletion.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newer.appendingPathComponent("marker").path))
        await catalog.close()
        await access.close()
    }

}

@MainActor
private struct CatalogFixture {
    let root: URL
    let defaults: UserDefaults
    let settings: AppSettings
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults = try XCTUnwrap(UserDefaults(suiteName: "model-catalog-\(root.lastPathComponent)"))
        defaults.set(root.path, forKey: "modelStoragePath")
        settings = AppSettings(service: SettingsStore(defaults: defaults))
    }
    func catalog(access: any ModelResourceAccess = LocalModelAccessGate(),
                 cleanup: @escaping ModelCatalog.StartupCleanupFactory = { _ in Task { 0 } }) -> ModelCatalog {
        ModelCatalog(settings: settings, log: Log(service: CatalogDiagnostics()), access: access,
                     textDownloads: TextModelDownloadOperations(download: { _, _, _ in }, validate: { _ in }),
                     artifacts: MLXModelArtifacts.text + MLXModelArtifacts.speech,
                     speechDescriptors: { MLXModelArtifacts.speechDescriptors }, startupStorageRoot: root, startupCleanup: cleanup)
    }
    func remove() {
        defaults.removePersistentDomain(forName: "model-catalog-\(root.lastPathComponent)")
        try? FileManager.default.removeItem(at: root)
    }
}

private actor CatalogLifetimeGate {
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        await withCheckedContinuation { waiter = $0 }
    }
    func waitUntilEntered() async { while !entered { await Task.yield() } }
    func release() { waiter?.resume(); waiter = nil }
}

private struct CatalogDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
