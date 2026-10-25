import UtterPresentationContracts
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
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
import UtterBuiltins
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterRuntime
import UtterUpdates
@testable import UtterPresentation

@MainActor
final class BuiltinCatalogTests: XCTestCase {
    func testShippedGraphValidatesEveryNativeFactoryWithoutActivatingIngress() async throws {
        let suite = "BuiltinCatalog-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let plugins = try BuiltinPlugins.registrations(defaults: defaults, directory: URL(fileURLWithPath: "/unused"),
            settings: settings, configuration: { throw CompositionStoreError.notLoaded })
        let catalog = try PluginCatalog(plugins)
        let resolver = try CompositionResolver(catalog: catalog, bundles: BuiltinCompositions.bundles(plugins),
            providers: BuiltinCompositions.providers)
        let effective = try resolver.resolve(BuiltinCompositions.shipped, legacy: BuiltinCompositions.legacy(settings.values))
        XCTAssertEqual(effective.mountedPluginIDs, Set(plugins.map { $0.descriptor.id }))
        XCTAssertTrue(effective.mountedPluginIDs.contains("session.execution"))
        XCTAssertTrue(effective.mountedPluginIDs.contains("mac.output"))
        XCTAssertTrue(effective.mountedPluginIDs.contains(UpdatePlugins.pluginID))
        XCTAssertEqual(plugins.filter { $0.descriptor.id == UpdatePlugins.pluginID }.count, 1)
        XCTAssertEqual(effective.bindings["speech"], "speech.apple")
    }

    func testRecoveryNeverMountsTheUpdater() {
        XCTAssertFalse(BuiltinCompositions.recoveryIDs.contains(UpdatePlugins.pluginID))
    }

    func testInvalidDocumentStartsOnlyRecoveryAndPreservesTheOriginalBytes() async throws {
        let suite = "BuiltinRecovery-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("plugins.json")
        let original = Data(#"{"schemaVersion":999,"bundles":["desktop"]}"#.utf8)
        try original.write(to: url)
        let application = try await BuiltinApplication.start(defaults: defaults, directory: directory)
        XCTAssertNotNil(application.compositionFailure)
        XCTAssertEqual(application.runtime.state, .ready)
        XCTAssertThrowsError(try application.runtime.service(AudioServices.capture))
        XCTAssertThrowsError(try application.runtime.service(MacServices.output))
        XCTAssertThrowsError(try application.runtime.service(MacServices.hotkeys))
        XCTAssertThrowsError(try application.runtime.service(GenerationServices.providers))
        XCTAssertThrowsError(try application.runtime.service(SessionServices.api))
        XCTAssertThrowsError(try application.runtime.service(UpdateServices.updater))
        XCTAssertEqual(try Data(contentsOf: url), original)
        try await application.stop()
    }

    func testRecoveryLeavesTheIntegrationsTabWithOnlyThePluginsSection() async throws {
        try await assertRecoveryTabs(writing: #"{"schemaVersion":999,"bundles":["desktop"]}"#)
    }

    func testRowUnknownToThisBuildStartsRecoveryOnTheSameTab() async throws {
        try await assertRecoveryTabs(
            writing: #"{"schemaVersion":1,"bundles":["desktop"],"plugins":[{"id":"presentation.removed-page"}]}"#)
    }

    private func assertRecoveryTabs(writing json: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let suite = "BuiltinRecoveryTabs-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("plugins.json")
        let original = Data(json.utf8)
        try original.write(to: url)
        let application = try await BuiltinApplication.start(defaults: defaults, directory: directory)
        XCTAssertNotNil(application.compositionFailure, file: file, line: line)
        let catalog = try application.runtime.service(PresentationServices.catalog)
        let tabs = SettingsTabLayout.tabs(from: catalog.contributions(for: .settings))
        XCTAssertEqual(tabs.map(\.id), [SettingsGroup.integrations.id], file: file, line: line)
        XCTAssertEqual(tabs.first?.members.map(\.id), ["presentation.configuration"], file: file, line: line)
        XCTAssertEqual(SettingsTabLayout.selection("presentation.models", in: tabs), SettingsGroup.integrations.id,
            file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: url), original, file: file, line: line)
        try await application.stop()
    }
}
