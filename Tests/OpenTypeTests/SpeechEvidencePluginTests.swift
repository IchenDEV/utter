import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterRuntime
@testable import UtterAudio

@MainActor
final class SpeechEvidencePluginTests: XCTestCase {
    func testFalseClassificationRemainsNoSpeechWithoutPublishingCancelledTrueResult() async throws {
        let plugin = AudioPlugins.speechEvidence { _, _ in false }
        let runtime = try await mount(plugin)
        let service = try runtime.service(AudioServices.evidence)
        let hasSpeech = try await service.containsSpeech(at: nil)
        XCTAssertFalse(hasSpeech)
        try await runtime.stop()
        do { _ = try await service.containsSpeech(at: nil); XCTFail("Retained service entered classifier") }
        catch is CancellationError { }
    }

    func testShutdownWaitsForNonCooperativeClassifierAndClosesAdmission() async throws {
        let barrier = EvidenceFixtureBarrier()
        let plugin = AudioPlugins.speechEvidence { _, _ in await barrier.hold(); return true }
        let runtime = try await mount(plugin)
        let service = try runtime.service(AudioServices.evidence)
        let analysis = Task { try await service.containsSpeech(at: URL(fileURLWithPath: "/caller.wav")) }
        await barrier.waitUntilHeld()
        let stop = Task { try await runtime.stop() }
        for _ in 0..<1_000 {
            if runtime.state == .stopping { break }
            await Task.yield()
        }
        XCTAssertEqual(runtime.state, .stopping)
        do { _ = try await service.containsSpeech(at: nil); XCTFail("Revoked ingress entered classifier") }
        catch is CancellationError { }
        await barrier.release()
        do { _ = try await analysis.value; XCTFail("Late classification published") }
        catch is CancellationError { }
        try await stop.value
    }

    private func mount(_ plugin: PluginRegistration) async throws -> PluginRuntime {
        let diagnostics = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.diagnostics", provides: [IntegrationServices.diagnostics.reference]
        )) { context, _ in try context.provide(IntegrationServices.diagnostics, value: EvidenceFixtureDiagnostics()) }
        let runtime = PluginRuntime(catalog: try PluginCatalog([diagnostics, plugin]))
        try await runtime.start([PluginSelection("fixture.diagnostics"), PluginSelection(plugin.descriptor.id)])
        return runtime
    }
}

private actor EvidenceFixtureBarrier {
    private var held: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func hold() async {
        await withCheckedContinuation { continuation in
            held = continuation
            let pending = waiters; waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }
    func waitUntilHeld() async {
        guard held == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { held?.resume(); held = nil }
}

private struct EvidenceFixtureDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
