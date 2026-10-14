import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
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
@testable import UtterRemoteMic

@MainActor
final class RemoteMicPluginTests: XCTestCase {
    private func fixture() throws -> (PluginRuntime, XiaomiRemoteMicBridge, RemotePluginSettings, () -> Int) {
        let settings = RemotePluginSettings()
        settings.values.remoteMicEnabled = false
        var injectedGain: () -> Double = { 0 }
        let bridge = XiaomiRemoteMicBridge(gainDB: { injectedGain() })
        var transports = 0
        bridge.installCentralTransportFactoryForTesting { [weak bridge] in
            transports += 1
            return ScopedRemoteTransport(bridge: bridge!)
        }
        let dependencies = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.data", provides: [DataServices.settings.reference, IntegrationServices.diagnostics.reference]
        )) { context, _ in
            try context.provide(DataServices.settings, value: settings)
            try context.provide(IntegrationServices.diagnostics, value: RemotePluginDiagnostics())
        }
        let plugin = RemoteMicPlugins.capture { gain in
            injectedGain = gain
            return bridge
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([dependencies, plugin]))
        return (runtime, bridge, settings, { transports })
    }

    func testColdRegistrationOperationalEnableAndRevokedVoiceCallbacks() async throws {
        let (runtime, bridge, settings, transportCount) = try fixture()
        try await runtime.start([PluginSelection("fixture.data"), PluginSelection("remote-mic.xiaomi")])
        let control = try runtime.service(RemoteMicServices.control)
        XCTAssertEqual(control.state, .idle)
        XCTAssertEqual(transportCount(), 0)
        settings.update { $0.remoteMicGainDB = 18 }
        XCTAssertEqual(bridge.gainDB(), 18)
        var presses = 0
        control.setVoiceCallbacks(pressed: { _ in presses += 1 }, released: nil, stopped: nil)
        let queuedPress = bridge.onVoiceKeyPressed
        queuedPress?(1)
        XCTAssertEqual(presses, 1)
        control.setEnabled(true)
        XCTAssertEqual(transportCount(), 1)
        try await runtime.stop()
        queuedPress?(2)
        control.setEnabled(true)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(transportCount(), 1)
        XCTAssertTrue(settings.observers.isEmpty)
    }

    func testCloseWaitsForTerminalConnectionCallbackAndKeepsOldTransport() async throws {
        let bridge = XiaomiRemoteMicBridge(gainDB: { 0 })
        var transport: ScopedRemoteTransport?
        bridge.installCentralTransportFactoryForTesting { [weak bridge] in
            let created = ScopedRemoteTransport(bridge: bridge!)
            transport = created
            return created
        }
        bridge.activate()
        bridge.simulateCentralStateForTesting(.poweredOn)
        _ = try XCTUnwrap(bridge.simulateCentralDiscoveryForTesting(peripheralIdentity: NSObject()))
        let cancelled = RemoteLifetimeSignal()
        transport?.onCancel = { cancelled.send() }
        var finished = false
        let close = Task {
            await bridge.close()
            finished = true
        }
        await cancelled.wait()
        XCTAssertFalse(finished)
        XCTAssertEqual(bridge.retiredCentralContextCountForTesting(), 1)
        XCTAssertEqual(transport?.cancelCount, 1)
        transport?.delegateProxy.deliverForTesting(.didDisconnect)
        await close.value
        XCTAssertTrue(finished)
        XCTAssertEqual(bridge.retiredCentralContextCountForTesting(), 0)
        bridge.activate()
        XCTAssertNil(bridge.centralTransportForTesting())
    }

    func testSettingsProjectionReceivesDiagnosticsAndDisposesItsObservers() async throws {
        let (runtime, bridge, _, _) = try fixture()
        try await runtime.start([PluginSelection("fixture.data"), PluginSelection("remote-mic.xiaomi")])
        let control = try runtime.service(RemoteMicServices.control)
        let platform = PlatformProjection(remote: control, login: nil, devices: nil, screen: nil,
            diagnostics: RemotePluginDiagnostics())
        XCTAssertNil(platform.remoteDiagnostics.lastCapture)
        bridge.noteCapture(.remote)
        XCTAssertEqual(platform.remoteDiagnostics.lastCapture, .remote)
        platform.dispose()
        bridge.noteCapture(.systemRemoteSilent)
        XCTAssertEqual(platform.remoteDiagnostics.lastCapture, .remote)
        try await runtime.stop()
    }

    func testCloseDrainsNonCooperativeOwnedTask() async {
        let bridge = XiaomiRemoteMicBridge(gainDB: { 0 })
        let entered = RemoteLifetimeSignal()
        let release = RemoteLifetimeSignal()
        let startedClose = RemoteLifetimeSignal()
        bridge.ownedTask {
            entered.send()
            await release.wait()
        }
        await entered.wait()
        var finished = false
        let close = Task {
            bridge.revoke()
            startedClose.send()
            await bridge.close()
            finished = true
        }
        await startedClose.wait()
        XCTAssertFalse(finished)
        XCTAssertEqual(bridge.ownedTasks.count, 1)
        release.send()
        await close.value
        XCTAssertTrue(finished)
        XCTAssertTrue(bridge.ownedTasks.isEmpty)
    }

    func testStreamGainRemainsFrozenUntilTheNextVoiceSession() {
        var gain: Double = 6
        let bridge = XiaomiRemoteMicBridge(gainDB: { gain })
        bridge.isActive = true
        bridge.handshake.markDecoderConfigured()
        bridge.handshake.markCapabilitiesRequested()
        XCTAssertTrue(bridge.handshake.confirmCapabilities(.default))
        let start = Data([0x04, 0, 0x02, 1])
        bridge.handleControl(start, attempt: 0)
        XCTAssertEqual(bridge.streamGainDB, 6)
        gain = 24
        bridge.handleControl(start, attempt: 0)
        XCTAssertEqual(bridge.streamGainDB, 6)
        bridge.endCapture()
        bridge.handleControl(start, attempt: 0)
        XCTAssertEqual(bridge.streamGainDB, 24)
    }

    func testRejectedCommitDeletesItsPreparedWAV() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = XiaomiRemoteMicBridge(gainDB: { 0 })
        bridge.isActive = true
        bridge.state = .ready(deviceName: "fixture")
        let token = bridge.beginSimulatedSessionForTesting()
        let capture = RemoteMicCaptureManager(
            bridge: bridge, log: Log(service: RemotePluginDiagnostics()), temporaryDirectory: directory
        )
        // File preparation succeeds; the real bridge rejects the commit without a connected peripheral.
        XCTAssertFalse(capture.start(token: token, levelUpdate: { _ in }, bufferUpdate: nil))
        XCTAssertNil(capture.lastRecordingURL)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
