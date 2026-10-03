import Foundation
import XCTest
import UtterContracts
import UtterRuntime
@testable import UtterData

@MainActor
final class DataPluginTests: XCTestCase {
    func testMemoryReadsTheHistorySelectedByTheRuntime() async throws {
        let name = "DataPlugins-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        let history = HistoryStore(directoryURL: directory, retention: { .forever }, reportError: { _ in })
        let replacement = PluginRegistration(descriptor: DataPlugins.history(directoryURL: directory, reportError: { _ in }).descriptor) { context, _ in
            try context.provide(DataServices.history, value: history)
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([DataPlugins.settings(defaults: defaults), replacement, DataPlugins.memory()]))
        try await runtime.start([PluginSelection("data.memory"), PluginSelection("data.history"), PluginSelection("data.settings")])
        let selected = try runtime.service(DataServices.history)
        let memory = try runtime.service(DataServices.memory)
        XCTAssertTrue(memory.recentContext(limit: 5, windowMinutes: 30, currentContext: nil).isEmpty)
        let record = InputRecord(rawText: "synthetic raw", processedText: "synthetic result", wasProcessed: true)
        selected.addRecord(record)
        XCTAssertEqual(history.records.first?.id, record.id)
        XCTAssertTrue(memory.recentContext(limit: 5, windowMinutes: 30, currentContext: nil).contains("synthetic result"))
        selected.updateUserFinalText(recordID: record.id, text: "synthetic correction")
        XCTAssertTrue(memory.recentContext(limit: 5, windowMinutes: 30, currentContext: nil).contains("synthetic correction"))
        try await runtime.stop()
    }

    func testBundledLexiconPluginSuppliesTheTypedService() async throws {
        let runtime = PluginRuntime(catalog: try PluginCatalog([DataPlugins.lexicons()]))
        try await runtime.start([PluginSelection("data.lexicons")])
        let service = try runtime.service(DataServices.lexicons)
        XCTAssertFalse(service.snapshot(for: .technology).recognitionPhrases.isEmpty)
        XCTAssertFalse(service.version.isEmpty)
        try await runtime.stop()
        XCTAssertThrowsError(try runtime.service(DataServices.lexicons))
    }

    func testReplacementUsesTheSameRuntimeAndServiceContract() async throws {
        struct Replacement: LexiconService {
            let version = "replacement"
            let sources: [IndustryLexiconSource] = []
            let packs: [IndustryLexiconPack] = []
            func snapshot(for id: IndustryLexiconID) -> IndustryLexiconSnapshot { .empty }
        }
        let replacement = PluginRegistration(descriptor: DataPlugins.lexicons().descriptor) { context, _ in
            try context.provide(DataServices.lexicons, value: Replacement())
        }
        let runtime = PluginRuntime(catalog: try PluginCatalog([replacement]))
        try await runtime.start([PluginSelection("data.lexicons")])
        XCTAssertEqual(try runtime.service(DataServices.lexicons).version, "replacement")
        try await runtime.stop()
    }
}
