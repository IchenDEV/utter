import AVFoundation
import XCTest
import UtterAudio
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
final class RemoteMicHostCapturePluginTests: XCTestCase {
    func testLocalRequestPreferringRemoteOpensHostSessionAndOwnsItsRecording() async throws {
        let source = HostCaptureSource()
        let runtime = try await mount(source)
        let capture = try runtime.service(AudioServices.capture)
        let recording = try await capture.begin(
            CaptureRequest(source: .local(deviceID: nil), preferRemoteMic: true), callbacks: CaptureCallbacks())
        XCTAssertEqual(source.hostStarts, 1)
        XCTAssertEqual(source.starts, [7])
        XCTAssertEqual(source.captureNotes, [.remote])
        let audio = try await recording.finish()
        XCTAssertEqual(audio.url, source.lastRecordingURL)
        XCTAssertEqual(source.stops, 1)
        XCTAssertEqual(source.cleanups, 0)
        await recording.close()
        XCTAssertEqual(source.cleanups, 1)
        try await runtime.stop()
    }

    func testRuntimeShutdownStopsHostCaptureAndRejectsLateLevels() async throws {
        let source = HostCaptureSource()
        let runtime = try await mount(source)
        var levels = 0
        let capture = try runtime.service(AudioServices.capture)
        _ = try await capture.begin(CaptureRequest(source: .local(deviceID: nil), preferRemoteMic: true),
            callbacks: CaptureCallbacks(level: { _ in levels += 1 }))
        source.level?(1)
        XCTAssertEqual(levels, 1)
        try await runtime.stop()
        source.level?(1)
        XCTAssertEqual(levels, 1)
        XCTAssertEqual(source.stops, 1)
        XCTAssertEqual(source.cleanups, 1)
    }

    private func mount(_ source: HostCaptureSource) async throws -> PluginRuntime {
        let fixture = PluginRegistration(descriptor: PluginDescriptor(id: "fixture.host-capture",
            provides: [RemoteMicServices.capture.reference, IntegrationServices.diagnostics.reference])) { context, _ in
            try context.provide(RemoteMicServices.capture, value: source)
            try context.provide(IntegrationServices.diagnostics, value: HostCaptureDiagnostics())
        }
        let plugins = [AudioPlugins.capture(), fixture]
        let runtime = PluginRuntime(catalog: try PluginCatalog(plugins))
        try await runtime.start(plugins.map { PluginSelection($0.descriptor.id) })
        return runtime
    }
}

private final class HostCaptureSource: RemoteCaptureSource {
    var currentSessionToken: UInt64?
    var isAvailable: Bool { true }
    var hasReceivedSamples: Bool { true }
    var thresholds = AudioActivityThresholds.default
    var lastRecordingURL: URL? { URL(fileURLWithPath: "/fixture-remote.wav") }
    var lastActivity = AudioCaptureActivity()
    var hostStarts = 0
    var starts: [UInt64] = []
    var stops = 0
    var cleanups = 0
    var captureNotes: [RemoteMicCaptureSource] = []
    var level: ((Float) -> Void)?
    func beginHostSession() -> UInt64? { hostStarts += 1; currentSessionToken = 7; return 7 }
    func cancelSession() { currentSessionToken = nil }
    func noteCapture(_ source: RemoteMicCaptureSource) { captureNotes.append(source) }
    func start(token: UInt64, levelUpdate: @escaping (Float) -> Void, bufferUpdate: ((AVAudioPCMBuffer) -> Void)?) -> Bool {
        starts.append(token)
        level = levelUpdate
        return true
    }
    func stop() { stops += 1; currentSessionToken = nil }
    func cleanupLastRecording() { cleanups += 1 }
}

private struct HostCaptureDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
