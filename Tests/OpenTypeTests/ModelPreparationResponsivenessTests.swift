import Foundation
import XCTest
@testable import UtterModels

final class ModelPreparationResponsivenessTests: XCTestCase {
    @MainActor
    func testGenerationPreparationKeepsMainActorResponsive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenTypePreparationResponsiveness-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = ModelStorage.generationStaging(for: UUID(), storageRoot: root)
        try ModelStorage.prepareGeneration(staging)
        let source = ModelStorage.hubModelRepoDir("org/model", downloadBase: staging.downloadBase)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: source.appendingPathComponent("config.json"))
        let weights = Data("preparation fixture".utf8)
        try weights.write(to: source.appendingPathComponent("weights.safetensors"))

        let gate = BackgroundWorkGate()
        let watchdog = Task.detached {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            gate.release()
        }
        defer {
            gate.release()
            watchdog.cancel()
        }
        let preparation = Task { @MainActor in
            try await ModelStorage.prepareGenerationCommitOffMainActor(
                kind: .llm, modelID: "org/model", staging: staging,
                onEnter: { gate.enterAndWait() }, onExit: { gate.exit() }
            )
        }
        let deadline = Date().addingTimeInterval(3)
        while !gate.snapshot().entered && Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let observed = gate.snapshot()
        gate.release()
        let prepared = try await preparation.value
        let copiedWeights = try Data(contentsOf: prepared.candidate.appendingPathComponent("weights.safetensors"))
        await ModelStorage.discardPreparedGenerationOffMainActor(prepared)

        XCTAssertTrue(observed.entered, "Preparation must enter its worker barrier")
        XCTAssertFalse(observed.exited, "MainActor must respond between worker entry and exit")
        XCTAssertTrue(gate.snapshot().exited)
        XCTAssertEqual(copiedWeights, weights)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.candidate.path))
    }
}
