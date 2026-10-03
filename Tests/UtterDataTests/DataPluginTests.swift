import XCTest
import UtterContracts
import UtterRuntime
@testable import UtterData

@MainActor
final class DataPluginTests: XCTestCase {
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
