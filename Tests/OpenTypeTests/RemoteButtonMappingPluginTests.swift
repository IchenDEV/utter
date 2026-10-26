import Foundation
import XCTest
import UtterContracts
import UtterMediaContracts
import UtterRuntime
@testable import UtterRemoteMic

@MainActor
final class RemoteButtonMappingPluginTests: XCTestCase {
    private let f5 = RemoteKeyMappingPolicy.ours
    private let service = RemoteKeyServiceFake()
    private let source = PluginPressSource()
    private let poster = PluginPoster()
    private let bridge = XiaomiRemoteMicBridge(gainDB: { 0 })
    private lazy var provider = RemoteKeyProviderFake([service])

    private func entry(_ button: RemoteButton) -> KeyMappingEntry {
        KeyMappingEntry(source: button.hidSource, destination: 0)
    }

    private func profile(_ buttons: RemoteButton...) -> RemoteButtonProfile {
        var profile = RemoteButtonProfile()
        for button in buttons { profile.set(.system(.mute), for: .single, of: button) }
        return profile
    }

    private func fixture(
        mappingEnabled: Bool, remapEnabled: Bool = true, profile: RemoteButtonProfile? = nil
    ) throws -> (PluginRuntime, RemotePluginSettings) {
        let settings = RemotePluginSettings()
        settings.values.remoteMicEnabled = false
        settings.values.remoteKeyRemapEnabled = remapEnabled
        settings.values.remoteButtonMappingEnabled = mappingEnabled
        settings.values.remoteButtonProfile = profile ?? self.profile(.right)
        let data = PluginRegistration(descriptor: PluginDescriptor(
            id: "fixture.data", provides: [DataServices.settings.reference, IntegrationServices.diagnostics.reference]
        )) { context, _ in
            try context.provide(DataServices.settings, value: settings)
            try context.provide(IntegrationServices.diagnostics, value: RemotePluginDiagnostics())
        }
        let plugin = RemoteMicPlugins.capture(
            makeBridge: { [bridge] _ in bridge },
            makeKeyRemap: { [provider] in RemoteKeyMappingController(provider: provider) },
            makeButtonMapping: { [source, poster] in
                RemoteButtonMappingParts(
                    source: source, poster: poster, isSecureInput: { false }, symbolicHotKeys: { nil }
                )
            }
        )
        return (PluginRuntime(catalog: try PluginCatalog([data, plugin])), settings)
    }

    private func start(_ runtime: PluginRuntime) async throws {
        try await runtime.start([PluginSelection("fixture.data"), PluginSelection("remote-mic.xiaomi")])
    }

    private func diagnostics(_ runtime: PluginRuntime) throws -> RemoteMicDiagnostics {
        try runtime.service(RemoteMicServices.control).diagnostics
    }

    func testMappingOffNeverOpensTheSourceOrWritesButtonEntries() async throws {
        let (runtime, _) = try fixture(mappingEnabled: false)
        try await start(runtime)
        XCTAssertEqual(service.entries, [f5])
        XCTAssertEqual(source.refreshes, [])
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .off)
        try await runtime.stop()
        XCTAssertEqual(source.stops, 0)
    }

    func testStoredSettingsAtLaunchSilenceTheKeyWithoutAskingForPermission() async throws {
        let (runtime, _) = try fixture(mappingEnabled: true)
        try await start(runtime)
        XCTAssertEqual(service.entries, [f5, entry(.right)])
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .active)
        XCTAssertFalse(source.refreshes.contains(true))
        try await runtime.stop()
    }

    func testTurningTheSettingOnAsksOnceAndReportsTheOutcome() async throws {
        source.status = .needsPermission(canAsk: true)
        source.statusAfterPrompt = .live
        let (runtime, settings) = try fixture(mappingEnabled: false)
        try await start(runtime)
        settings.update { $0.remoteButtonMappingEnabled = true }
        XCTAssertEqual(source.refreshes.filter { $0 }.count, 1)
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .active)
        XCTAssertEqual(service.entries, [f5, entry(.right)])
        try await runtime.stop()
    }

    func testWithoutPermissionNothingIsSilencedAndThePageCanAskAgain() async throws {
        source.status = .needsPermission(canAsk: true)
        source.statusAfterPrompt = .live
        let (runtime, _) = try fixture(mappingEnabled: true)
        try await start(runtime)
        XCTAssertEqual(service.entries, [f5])
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .needsPermission(canAsk: true))
        try runtime.service(RemoteMicServices.control).requestButtonMappingPermission()
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .active)
        XCTAssertEqual(service.entries, [f5, entry(.right)])
        try await runtime.stop()
    }

    func testRefreshFromThePageChecksTheSourceAgain() async throws {
        source.status = .needsPermission(canAsk: false)
        let (runtime, _) = try fixture(mappingEnabled: true)
        try await start(runtime)
        let before = source.refreshes.count
        source.status = .live
        try runtime.service(RemoteMicServices.control).refreshButtonMapping()
        XCTAssertEqual(source.refreshes.count, before + 1)
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .active)
        try await runtime.stop()
    }

    func testTurningTheRemapOffRemovesTheSilenceBeforeTheObserverStops() async throws {
        let (runtime, settings) = try fixture(mappingEnabled: true)
        try await start(runtime)
        var entriesWhenStopped: [KeyMappingEntry]?
        source.onStop = { [service] in entriesWhenStopped = service.entries }
        settings.update { $0.remoteKeyRemapEnabled = false }
        XCTAssertEqual(entriesWhenStopped, [f5])
        XCTAssertEqual(service.entries, [])
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .off)
        settings.update { $0.remoteKeyRemapEnabled = true }
        XCTAssertEqual(service.entries, [f5, entry(.right)])
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .active)
        try await runtime.stop()
    }

    func testKillSwitchOffKeepsTheMappingFromTouchingAnything() async throws {
        let (runtime, _) = try fixture(mappingEnabled: true, remapEnabled: false)
        try await start(runtime)
        XCTAssertEqual(service.writes, 0)
        XCTAssertEqual(source.refreshes, [])
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .off)
        try await runtime.stop()
    }

    func testStoppingTheRuntimeRestoresForeignEntriesAndStopsTheObserver() async throws {
        let other = KeyMappingEntry(source: 0x7_0000_0039, destination: 0x7_0000_0029)
        service.entries = [other]
        let (runtime, _) = try fixture(mappingEnabled: true)
        try await start(runtime)
        XCTAssertEqual(service.entries, [other, f5, entry(.right)])
        let control = try runtime.service(RemoteMicServices.control)
        try await runtime.stop()
        XCTAssertEqual(service.entries, [other])
        XCTAssertEqual(source.stops, 1)
        XCTAssertEqual(control.diagnostics.buttonMapping, .off)
    }

    func testEditingTheProfileRetargetsWithoutCountingAReapply() async throws {
        let (runtime, settings) = try fixture(mappingEnabled: true)
        try await start(runtime)
        settings.update { $0.remoteButtonProfile = profile(.right, .left) }
        XCTAssertEqual(service.entries.map(\.source).sorted(), [f5, entry(.right), entry(.left)].map(\.source).sorted())
        XCTAssertTrue(service.entries.allSatisfy { $0.destination == 0 })
        settings.update { $0.remoteButtonProfile = profile(.left) }
        XCTAssertEqual(service.entries, [f5, entry(.left)])
        XCTAssertEqual(try diagnostics(runtime).keyRemapReapplyCount, 0)
        try await runtime.stop()
    }

    func testAPressRunsTheBoundActionThroughThePoster() async throws {
        let (runtime, _) = try fixture(mappingEnabled: true)
        try await start(runtime)
        source.press(.right)
        source.release(.right)
        XCTAssertEqual(poster.posted, [.media(key: 7, down: true), .media(key: 7, down: false)])
        try await runtime.stop()
        source.press(.right)
        XCTAssertEqual(poster.posted.count, 2)
    }

    func testButtonStateFollowsTheKeyMappingWhenTheRemoteAppearsLate() async throws {
        provider.services = []
        let (runtime, _) = try fixture(mappingEnabled: true)
        try await start(runtime)
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .waitingForRemote)
        XCTAssertEqual(service.entries, [])
        provider.services = [service]
        bridge.state = .ready(deviceName: "fixture")
        XCTAssertEqual(service.entries, [f5, entry(.right)])
        XCTAssertEqual(try diagnostics(runtime).buttonMapping, .active)
        try await runtime.stop()
    }
}
