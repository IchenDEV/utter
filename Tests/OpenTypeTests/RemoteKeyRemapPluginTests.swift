import Foundation
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterRuntime
@testable import UtterRemoteMic

@MainActor
final class RemoteKeyRemapPluginTests: XCTestCase {
    private let ours = RemoteKeyMappingPolicy.ours

    private func fixture(
        _ provider: RemoteKeyProviderFake, remapEnabled: Bool = true
    ) throws -> (PluginRuntime, XiaomiRemoteMicBridge, RemotePluginSettings) {
        let settings = RemotePluginSettings()
        settings.values.remoteMicEnabled = false
        settings.values.remoteKeyRemapEnabled = remapEnabled
        let bridge = XiaomiRemoteMicBridge(gainDB: { 0 })
        let data = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.data", provides: [DataServices.settings.reference, IntegrationServices.diagnostics.reference]
        )) { context, _ in
            try context.provide(DataServices.settings, value: settings)
            try context.provide(IntegrationServices.diagnostics, value: RemotePluginDiagnostics())
        }
        let plugin = RemoteMicPlugins.capture(
            makeBridge: { _ in bridge },
            makeKeyRemap: { RemoteKeyMappingController(provider: provider) }
        )
        return (PluginRuntime(catalog: try PluginCatalog([data, plugin])), bridge, settings)
    }

    private func start(_ runtime: PluginRuntime) async throws {
        try await runtime.start([PluginSelection("fixture.data"), PluginSelection("remote-mic.xiaomi")])
    }

    func testRemapIsAppliedOnReadyEvenWithTheRemoteMicOff() async throws {
        let service = RemoteKeyServiceFake()
        let (runtime, _, settings) = try fixture(RemoteKeyProviderFake([service]))
        try await start(runtime)
        XCTAssertFalse(settings.values.remoteMicEnabled)
        XCTAssertEqual(service.entries, [ours])
        let control = try runtime.service(RemoteMicServices.control)
        XCTAssertEqual(control.diagnostics.keyRemap, .active)
        try await runtime.stop()
    }

    func testStoppingTheRuntimeRestoresTheMapping() async throws {
        let other = KeyMappingEntry(source: 0x7_0000_0039, destination: 0x7_0000_0029)
        let service = RemoteKeyServiceFake(entries: [other])
        let (runtime, _, _) = try fixture(RemoteKeyProviderFake([service]))
        try await start(runtime)
        XCTAssertEqual(service.entries, [other, ours])
        try await runtime.stop()
        XCTAssertEqual(service.entries, [other])
    }

    func testTurningTheSettingOffRestoresAndOnAppliesAgain() async throws {
        let service = RemoteKeyServiceFake()
        let (runtime, _, settings) = try fixture(RemoteKeyProviderFake([service]))
        try await start(runtime)
        let control = try runtime.service(RemoteMicServices.control)
        settings.update { $0.remoteKeyRemapEnabled = false }
        XCTAssertEqual(service.entries, [])
        XCTAssertEqual(control.diagnostics.keyRemap, .off)
        settings.update { $0.remoteKeyRemapEnabled = true }
        XCTAssertEqual(service.entries, [ours])
        XCTAssertEqual(control.diagnostics.keyRemap, .active)
        try await runtime.stop()
    }

    func testDisabledSettingNeverTouchesTheDevice() async throws {
        let service = RemoteKeyServiceFake()
        let (runtime, _, _) = try fixture(RemoteKeyProviderFake([service]), remapEnabled: false)
        try await start(runtime)
        XCTAssertEqual(service.writes, 0)
        XCTAssertEqual(try runtime.service(RemoteMicServices.control).diagnostics.keyRemap, .off)
        try await runtime.stop()
        XCTAssertEqual(service.writes, 0)
    }

    func testRemapStateIsMergedIntoDiagnosticsWithoutDisturbingBridgeFields() async throws {
        let (runtime, bridge, _) = try fixture(RemoteKeyProviderFake([RemoteKeyServiceFake()]))
        try await start(runtime)
        let control = try runtime.service(RemoteMicServices.control)
        var seen: [RemoteMicDiagnostics] = []
        let id = control.observeDiagnostics { seen.append($0) }
        bridge.noteCapture(.remote)
        let latest = try XCTUnwrap(seen.last)
        XCTAssertEqual(latest.lastCapture, .remote)
        XCTAssertEqual(latest.keyRemap, .active)
        control.removeObserver(id)
        try await runtime.stop()
    }

    func testBridgeReadyReportsWaitingWhenTheHIDServiceIsNotVisibleYet() async throws {
        let provider = RemoteKeyProviderFake()
        let (runtime, bridge, _) = try fixture(provider)
        try await start(runtime)
        let control = try runtime.service(RemoteMicServices.control)
        XCTAssertEqual(control.diagnostics.keyRemap, .noRemote)
        bridge.state = .ready(deviceName: "fixture")
        XCTAssertEqual(control.diagnostics.keyRemap, .waitingForService)
        let service = RemoteKeyServiceFake()
        provider.services = [service]
        bridge.state = .ready(deviceName: "fixture")
        XCTAssertEqual(service.entries, [ours])
        XCTAssertEqual(control.diagnostics.keyRemap, .active)
        try await runtime.stop()
    }

    func testStoppingPublishesTheOffState() async throws {
        let (runtime, _, _) = try fixture(RemoteKeyProviderFake([RemoteKeyServiceFake()]))
        try await start(runtime)
        let control = try runtime.service(RemoteMicServices.control)
        try await runtime.stop()
        XCTAssertEqual(control.diagnostics.keyRemap, .off)
    }
}
