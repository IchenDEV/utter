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
import AVFoundation
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterRuntime
@testable import UtterAudio

@MainActor
final class CapturePluginTests: XCTestCase {
    func testTailBuffersAreAcceptedUntilTheDriverFinishesStopping() async throws {
        let driver = FixtureCaptureDriver()
        let runtime = try await mount { _, _, _ in driver }
        let service = try runtime.service(AudioServices.capture)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        buffer.frameLength = 1
        var buffers = 0
        let recording = try await service.begin(request, callbacks: CaptureCallbacks(buffer: { _ in buffers += 1 }))
        driver.callbacks?.buffer?(buffer)
        driver.onStop = { driver.callbacks?.buffer?(buffer) }
        _ = try await recording.finish()
        XCTAssertEqual(buffers, 2)
        XCTAssertEqual(driver.flushes, [true])
        driver.callbacks?.buffer?(buffer)
        XCTAssertEqual(buffers, 2)
        await recording.close()
        try await runtime.stop()
    }

    func testRegistrationIsColdAndRecordingOwnsFileUntilExplicitCleanup() async throws {
        let driver = FixtureCaptureDriver()
        var constructions = 0
        let runtime = try await mount { _, _, _ in constructions += 1; return driver }
        XCTAssertEqual(constructions, 0)
        let service = try runtime.service(AudioServices.capture)
        var levels = 0
        let recording = try await service.begin(request, callbacks: CaptureCallbacks(level: { _ in levels += 1 }))
        driver.callbacks?.level(1)
        XCTAssertEqual(levels, 1)
        let first = try await recording.finish()
        let second = try await recording.finish()
        XCTAssertEqual(first.url, second.url)
        XCTAssertEqual(driver.stops, 1)
        XCTAssertEqual(driver.cleanups, 0)
        driver.callbacks?.level(1)
        XCTAssertEqual(levels, 1)
        do { _ = try await service.begin(request, callbacks: CaptureCallbacks()); XCTFail("Recording still owns its file") }
        catch CaptureError.busy { }
        await recording.close()
        await recording.close()
        XCTAssertEqual(driver.cleanups, 1)
        try await runtime.stop()
        XCTAssertEqual(driver.cleanups, 1)
    }

    func testShutdownWaitsForLateCaptureStartAndRejectsItsCallbacks() async throws {
        let barrier = CaptureFixtureBarrier()
        let driver = FixtureCaptureDriver(startBarrier: barrier)
        let runtime = try await mount { _, _, _ in driver }
        let service = try runtime.service(AudioServices.capture)
        var levels = 0
        let begin = Task { try await service.begin(self.request, callbacks: CaptureCallbacks(level: { _ in levels += 1 })) }
        await barrier.waitUntilHeld()
        let stop = Task { try await runtime.stop() }
        for _ in 0..<1_000 {
            if runtime.state == .stopping { break }
            await Task.yield()
        }
        driver.callbacks?.level(1)
        XCTAssertEqual(levels, 0)
        XCTAssertEqual(driver.cleanups, 0)
        do { _ = try await service.begin(request, callbacks: CaptureCallbacks()); XCTFail("Revoked ingress") }
        catch is CancellationError { }
        await barrier.release()
        do { _ = try await begin.value; XCTFail("Late start published a recording") }
        catch is CancellationError { }
        try await stop.value
        XCTAssertEqual(driver.stops, 1)
        XCTAssertEqual(driver.cleanups, 1)
    }

    func testShutdownDrainsFinishBeforeDeletingOwnedFile() async throws {
        let barrier = CaptureFixtureBarrier()
        let driver = FixtureCaptureDriver(stopBarrier: barrier)
        let runtime = try await mount { _, _, _ in driver }
        let service = try runtime.service(AudioServices.capture)
        let recording = try await service.begin(request, callbacks: CaptureCallbacks())
        let finish = Task { try await recording.finish() }
        await barrier.waitUntilHeld()
        let stop = Task { try await runtime.stop() }
        for _ in 0..<1_000 {
            if runtime.state == .stopping { break }
            await Task.yield()
        }
        XCTAssertEqual(driver.cleanups, 0)
        await barrier.release()
        do { _ = try await finish.value; XCTFail("Revoked finish published audio") }
        catch is CancellationError { }
        try await stop.value
        XCTAssertEqual(driver.stops, 1)
        XCTAssertEqual(driver.cleanups, 1)
    }

    func testMissingRemoteSourceRejectsCaptureWithoutOpeningLocalMicrophone() async throws {
        let runtime = try await mountProduction()
        let service = try runtime.service(AudioServices.capture)
        do {
            _ = try await service.begin(CaptureRequest(source: .remote(token: 5)), callbacks: CaptureCallbacks())
            XCTFail("Missing source started capture")
        } catch CaptureError.remoteUnavailable { }
        try await runtime.stop()
    }

    func testOldRemoteTokenDoesNotStopOrDeleteCurrentSourceRecording() async throws {
        let source = FixtureRemoteSource()
        let driver = RemoteCaptureDriver(source: source)
        do { try await driver.start(CaptureRequest(source: .remote(token: 4)), callbacks: CaptureCallbacks()); XCTFail("Old token admitted") }
        catch CaptureError.remoteUnavailable { }
        _ = await driver.stop(flushTail: false)
        await driver.cleanup()
        XCTAssertEqual(source.starts, 0)
        XCTAssertEqual(source.stops, 0)
        XCTAssertEqual(source.cleanups, 0)
    }

    private var request: CaptureRequest { CaptureRequest(source: .local(deviceID: nil)) }
    private func mount(
        _ factory: @escaping (CaptureRequest, (any RemoteCaptureSource)?, UtterContracts.Log) throws -> any CaptureDriver
    ) async throws -> PluginRuntime {
        try await boot(AudioPlugins.capture(makeDriver: factory))
    }
    private func mountProduction() async throws -> PluginRuntime { try await boot(AudioPlugins.capture()) }
    private func boot(_ capture: PluginRegistration) async throws -> PluginRuntime {
        let diagnostics = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.diagnostics", provides: [IntegrationServices.diagnostics.reference]
        )) { context, _ in try context.provide(IntegrationServices.diagnostics, value: CaptureFixtureDiagnostics()) }
        let plugins = [capture, diagnostics]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        return runtime
    }
}

@MainActor
private final class FixtureCaptureDriver: CaptureDriver {
    let startBarrier: CaptureFixtureBarrier?
    let stopBarrier: CaptureFixtureBarrier?
    var callbacks: CaptureCallbacks?
    var stops = 0
    var cleanups = 0
    var flushes: [Bool] = []
    var onStop: (() -> Void)?
    init(startBarrier: CaptureFixtureBarrier? = nil, stopBarrier: CaptureFixtureBarrier? = nil) {
        self.startBarrier = startBarrier
        self.stopBarrier = stopBarrier
    }
    func start(_ request: CaptureRequest, callbacks: CaptureCallbacks) async throws {
        self.callbacks = callbacks
        await startBarrier?.hold()
    }
    func stop(flushTail: Bool) async -> CapturedAudio {
        stops += 1
        flushes.append(flushTail)
        onStop?()
        await stopBarrier?.hold()
        return CapturedAudio(url: URL(fileURLWithPath: "/owned-recording.wav"), activity: AudioCaptureActivity())
    }
    func cleanup() async { cleanups += 1 }
}

private actor CaptureFixtureBarrier {
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

private final class FixtureRemoteSource: RemoteCaptureSource {
    var isAvailable: Bool { true }
    var hasReceivedSamples: Bool { true }
    func beginHostSession() -> UInt64? { nil }
    func cancelSession() {}
    func noteCapture(_ source: RemoteMicCaptureSource) {}
    var currentSessionToken: UInt64? { 5 }
    var thresholds = AudioActivityThresholds.default
    var lastRecordingURL: URL? { URL(fileURLWithPath: "/current-recording.wav") }
    var lastActivity = AudioCaptureActivity()
    var starts = 0
    var stops = 0
    var cleanups = 0
    func start(token: UInt64, levelUpdate: @escaping (Float) -> Void, bufferUpdate: ((AVAudioPCMBuffer) -> Void)?) -> Bool { starts += 1; return true }
    func stop() { stops += 1 }
    func cleanupLastRecording() { cleanups += 1 }
}

private struct CaptureFixtureDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
