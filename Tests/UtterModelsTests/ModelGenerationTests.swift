import Foundation
import XCTest
@testable import UtterModels

final class ModelGenerationTests: XCTestCase {
    private enum InjectedFailure: Error { case replacement }

    func testPublicationMaterializesSymlinksBeforeStagingRemoval() throws {
        try withFixture { fixture in
            let blob = fixture.root.appendingPathComponent("hub/blob")
            try FileManager.default.createDirectory(at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("weights".utf8).write(to: blob)
            try FileManager.default.createDirectory(at: fixture.source, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: fixture.source.appendingPathComponent("config.json"))
            try FileManager.default.createSymbolicLink(at: fixture.source.appendingPathComponent("weights.safetensors"), withDestinationURL: blob)
            let prepared = try fixture.prepare()
            defer { ModelGenerations.discardPreparedGeneration(prepared) }
            try ModelGenerations.publishPreparedGeneration(prepared)
            try FileManager.default.removeItem(at: fixture.source)
            try FileManager.default.removeItem(at: blob)
            let weights = fixture.destination.appendingPathComponent("weights.safetensors")
            XCTAssertEqual(try Data(contentsOf: weights), Data("weights".utf8))
            let attributes = try FileManager.default.attributesOfItem(atPath: weights.path)
            XCTAssertNotEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
            XCTAssertTrue(ModelAssets.llmRepoIsComplete(at: fixture.destination))
        }
    }

    func testFailedPublicationRestoresPreviousModelAfterCandidateWasMoved() throws {
        try withFixture { fixture in
            try fixture.writeModel("old", at: fixture.destination)
            try fixture.writeModel("new", at: fixture.source)
            let prepared = try fixture.prepare()
            defer { ModelGenerations.discardPreparedGeneration(prepared) }
            XCTAssertThrowsError(try ModelGenerations.publishPreparedGeneration(prepared) { candidate, destination in
                try FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: candidate, to: destination)
                throw InjectedFailure.replacement
            }) { error in
                XCTAssertTrue(error is InjectedFailure, "Unexpected restoration failure: \(error)")
            }
            try fixture.assertModel("old", at: fixture.destination)
        }
    }

    func testFailedPublicationRestoresPreviousModelWhenDestinationIsPartialFile() throws {
        try withFixture { fixture in
            try fixture.writeModel("old", at: fixture.destination)
            try fixture.writeModel("new", at: fixture.source)
            let prepared = try fixture.prepare()
            defer { ModelGenerations.discardPreparedGeneration(prepared) }
            XCTAssertThrowsError(try ModelGenerations.publishPreparedGeneration(prepared) { _, destination in
                try FileManager.default.removeItem(at: destination)
                try Data("partial replacement".utf8).write(to: destination)
                throw InjectedFailure.replacement
            }) { error in
                XCTAssertTrue(error is InjectedFailure, "Unexpected restoration failure: \(error)")
            }
            try fixture.assertModel("old", at: fixture.destination)
        }
    }

    func testFailedRestorationKeepsBackupAcrossDiscardAndRestartCleanup() throws {
        try withFixture { fixture in
            try fixture.writeModel("old", at: fixture.destination)
            try fixture.writeModel("new", at: fixture.source)
            let prepared = try fixture.prepare()
            var recoveryURL: URL?
            do {
                try ModelGenerations.publishRestoringGeneration(
                    prepared,
                    restoration: { _, _ in throw InjectedFailure.replacement },
                    replacement: { _, _ in throw InjectedFailure.replacement }
                )
                XCTFail("Expected failed restoration")
            } catch ModelGenerationError.restorationFailed(let backup, _) {
                recoveryURL = backup
            }
            ModelGenerations.discardPreparedGeneration(prepared)
            _ = ModelGenerations.cleanupOrphanedGenerationStaging(storageRoot: fixture.root)
            try fixture.assertModel("old", at: XCTUnwrap(recoveryURL))
        }
    }

    func testMissingStagedSourceLeavesPublishedModelUntouched() throws {
        try withFixture { fixture in
            try fixture.writeModel("old", at: fixture.destination)
            XCTAssertThrowsError(try fixture.prepare()) { error in
                guard case ModelGenerationError.missingSource = error else { return XCTFail("Unexpected error: \(error)") }
            }
            try fixture.assertModel("old", at: fixture.destination)
        }
    }

    func testSymlinkCycleRejectsCandidateAndPreservesPublishedModel() throws {
        try withFixture { fixture in
            try fixture.writeModel("old", at: fixture.destination)
            try FileManager.default.createDirectory(at: fixture.source, withIntermediateDirectories: true)
            let first = fixture.source.appendingPathComponent("first")
            let second = fixture.source.appendingPathComponent("second")
            try FileManager.default.createSymbolicLink(at: first, withDestinationURL: second)
            try FileManager.default.createSymbolicLink(at: second, withDestinationURL: first)
            XCTAssertThrowsError(try fixture.prepare()) { error in
                guard case ModelGenerationError.symlinkCycle = error else { return XCTFail("Unexpected error: \(error)") }
            }
            try fixture.assertModel("old", at: fixture.destination)
        }
    }

    func testStartupCleanupRemovesManagedArtifactsAndKeepsPublishedModel() throws {
        try withFixture { fixture in
            try fixture.writeModel("old", at: fixture.destination)
            try fixture.writeModel("new", at: fixture.source)
            let prepared = try fixture.prepare()
            let generations = fixture.root.appendingPathComponent(ModelGenerations.generationDirectoryName)
            let first = generations.appendingPathComponent(UUID().uuidString)
            let second = generations.appendingPathComponent(UUID().uuidString)
            let retired = fixture.root.appendingPathComponent(ModelGenerations.cleanupDirectoryName).appendingPathComponent("retired")
            let unrelated = fixture.root.appendingPathComponent("user-folder")
            for directory in [first, second, retired, unrelated] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data("keep".utf8).write(to: directory.appendingPathComponent("file"))
            }
            let retiredFile = retired.deletingLastPathComponent().appendingPathComponent("partial-file")
            try Data("partial".utf8).write(to: retiredFile)
            XCTAssertEqual(ModelGenerations.cleanupOrphanedGenerationStaging(storageRoot: fixture.root), 6)
            XCTAssertFalse(FileManager.default.fileExists(atPath: retiredFile.path))
            for directory in [first, second, retired, prepared.candidate] {
                XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(prepared.backup).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
            try fixture.assertModel("old", at: fixture.destination)
        }
    }

    private func withFixture(_ operation: (GenerationFixture) throws -> Void) throws {
        let fixture = GenerationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try operation(fixture)
    }
}

private struct GenerationFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var source: URL { root.appendingPathComponent("staged/model") }
    var destination: URL { root.appendingPathComponent("models/model") }

    func prepare() throws -> PreparedModelGeneration {
        try ModelGenerations.prepare(source: source, destination: destination, storageRoot: root)
    }

    func writeModel(_ value: String, at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["config.json", "weights.safetensors"] {
            try Data(value.utf8).write(to: directory.appendingPathComponent(name))
        }
    }

    func assertModel(_ value: String, at directory: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        for name in ["config.json", "weights.safetensors"] {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), Data(value.utf8), file: file, line: line)
        }
    }
}
