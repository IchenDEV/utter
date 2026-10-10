import Foundation
import XCTest
import UtterContracts
import UtterRuntime
@testable import UtterData

@MainActor
final class CompositionTests: XCTestCase {
    private func resolver() throws -> CompositionResolver {
        let plugins = ["speech.apple", "speech.whisper"].map { id in
            PluginRegistration(descriptor: PluginDescriptor(id: id), validate: { configuration in
                guard Set(configuration.keys).isSubset(of: ["first", "second"]) else {
                    throw PluginRuntimeError.invalidConfiguration(id)
                }
            }) { _, _ in }
        }
        return try CompositionResolver(
            catalog: PluginCatalog(plugins),
            bundles: [
                CompositionLayer("desktop", plugins: [
                    PluginConfigurationRow("speech.apple", configuration: ["first": .number(1), "second": .number(2)]),
                    PluginConfigurationRow("speech.whisper"),
                ], bindings: ["speech": "apple"]),
                CompositionLayer("override", plugins: [PluginConfigurationRow("speech.apple", configuration: ["first": .number(3)])]),
            ],
            providers: [
                ProviderBindingDescriptor(capability: "speech", providerID: "apple", pluginID: "speech.apple"),
                ProviderBindingDescriptor(capability: "speech", providerID: "whisper", pluginID: "speech.whisper"),
            ]
        )
    }

    func testLegacyPreferenceOverridesDefaultsAndExplicitPreferenceOverridesLegacy() async throws {
        let resolver = try resolver()
        let legacy = CompositionLayer("legacy", bindings: ["speech": "whisper"])
        let inherited = try resolver.resolve(CompositionDocument(bundles: ["desktop"]), legacy: legacy)
        XCTAssertEqual(inherited.bindings["speech"], "whisper")
        let explicit = try resolver.resolve(CompositionDocument(bundles: ["desktop"], bindings: ["speech": "apple"]), legacy: legacy)
        XCTAssertEqual(explicit.bindings["speech"], "apple")
    }

    func testOrderedLayersReplaceTheEntireRowWithoutDeepMerging() async throws {
        let resolved = try resolver().resolve(CompositionDocument(bundles: ["desktop", "override"]))
        let row = try XCTUnwrap(resolved.plugins.first { $0.id == "speech.apple" })
        XCTAssertEqual(row.configuration, ["first": .number(3)])
    }

    func testInvalidSelectionMatrixFailsClosed() async throws {
        let resolver = try resolver()
        let invalid: [CompositionDocument] = [
            CompositionDocument(schemaVersion: 2, bundles: ["desktop"]),
            CompositionDocument(bundles: ["unknown"]),
            CompositionDocument(bundles: ["desktop", "desktop"]),
            CompositionDocument(bundles: ["desktop"], plugins: [PluginConfigurationRow("speech.apple"), PluginConfigurationRow("speech.apple")]),
            CompositionDocument(bundles: ["desktop"], plugins: [PluginConfigurationRow("unknown")]),
            CompositionDocument(bundles: ["desktop"], plugins: [PluginConfigurationRow("speech.apple", enabled: false)]),
            CompositionDocument(bundles: ["desktop"], bindings: ["unknown": "apple"]),
            CompositionDocument(bundles: ["desktop"], bindings: ["speech": "unknown"]),
            CompositionDocument(bundles: ["desktop"], plugins: [PluginConfigurationRow("speech.whisper", enabled: false, configuration: ["apiKey": .string("secret")])]),
        ]
        for document in invalid { XCTAssertThrowsError(try resolver.resolve(document)) }
    }

    func testJSONRejectsUnknownFieldsAndFutureVersions() async throws {
        let invalid = [
            #"{"schemaVersion":1,"bundles":[],"typo":true}"#,
            #"{"schemaVersion":1,"bundles":[],"plugins":[{"id":"speech.apple","enabeld":false}]}"#,
            #"{"schemaVersion":99,"bundles":[]}"#,
        ]
        for json in invalid {
            XCTAssertThrowsError(try JSONDecoder().decode(CompositionDocument.self, from: Data(json.utf8)))
        }
    }

    func testSavedStructureWaitsForRestartAndOrdinaryBindingsApplyToNextSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CompositionStore(fileURL: directory.appendingPathComponent("composition.json"), resolver: resolver(), shipped: CompositionDocument(bundles: ["desktop"]))
        let mounted = try store.load()
        try store.save(CompositionDocument(bundles: ["desktop"], bindings: ["speech": "whisper"]))
        XCTAssertFalse(store.restartRequired)
        XCTAssertEqual(try store.sessionSnapshot.bindings["speech"], "whisper")
        try store.save(CompositionDocument(bundles: ["desktop"], plugins: [PluginConfigurationRow("speech.apple", enabled: false)], bindings: ["speech": "whisper"]))
        XCTAssertTrue(store.restartRequired)
        XCTAssertEqual(store.mounted, mounted)
        XCTAssertTrue(try store.sessionSnapshot.mountedPluginIDs.contains("speech.apple"))
        let restarted = try CompositionStore(fileURL: store.fileURL, resolver: resolver(), shipped: CompositionDocument(bundles: ["desktop"]))
        XCTAssertFalse(try restarted.load().mountedPluginIDs.contains("speech.apple"))
    }

    func testCorruptDocumentIsPreservedAndExplicitResetCreatesUnchangedBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("composition.json")
        let original = Data("broken user composition".utf8)
        try original.write(to: url)
        let store = try CompositionStore(fileURL: url, resolver: resolver(), shipped: CompositionDocument(bundles: ["desktop"]))
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: url), original)
        let backup = try XCTUnwrap(store.resetToShipped())
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try store.load().bindings["speech"], "apple")
    }

    func testInvalidSaveDoesNotReplaceValidDocument() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CompositionStore(fileURL: directory.appendingPathComponent("composition.json"), resolver: resolver(), shipped: CompositionDocument(bundles: ["desktop"]))
        _ = try store.load()
        try store.save(CompositionDocument(bundles: ["desktop"]))
        let before = try Data(contentsOf: store.fileURL)
        XCTAssertThrowsError(try store.save(CompositionDocument(bundles: ["missing"])))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
    }
}
