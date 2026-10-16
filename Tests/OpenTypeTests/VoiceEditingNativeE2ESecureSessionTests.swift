import XCTest
import UtterContracts
import UtterData
import UtterMediaContracts
import UtterModels
import UtterProcessing
import UtterRuntime
@testable import UtterMacServices
@testable import UtterSession

@MainActor
final class VoiceEditingNativeE2ESecureSessionTests: XCTestCase {
    func testRefusedLocalTargetCannotBecomeUnselectedCommandDictationOrOutput() async throws {
        for mode in [TextProcessingMode.command, .formatting, .direct] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.targetAvailable = false
            try await fixture.start()
            let execution = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text("Synthetic dictation"), mode: mode)
            do {
                try execution.start(intent)
                _ = try await execution.waitForCompletion(intent.id)
                XCTFail("Refused local capture was admitted")
            } catch { XCTAssertEqual(error as? DeliveryError, .invalidTarget) }
            XCTAssertTrue(fixture.capture.requests.isEmpty)
            XCTAssertTrue(fixture.screen.requests.isEmpty)
            XCTAssertTrue(fixture.recipeCreations.isEmpty)
            XCTAssertTrue(fixture.recipe.requests.isEmpty)
            XCTAssertTrue(fixture.output.requests.isEmpty)
            XCTAssertTrue(try fixture.runtime.service(DataServices.history).records.isEmpty)
            try await fixture.runtime.stop()
        }
    }

    func testValidUnselectedCommandStillUsesScreenContext() async throws {
        for selection in [nil, ""] as [String?] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.target.selectedText = selection
            try await fixture.start()
            let execution = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text("Synthetic command"), mode: .command)
            try execution.start(intent)
            _ = try await execution.waitForCompletion(intent.id)
            XCTAssertEqual(fixture.screen.requests.count, 1)
            XCTAssertEqual(fixture.recipe.requests.count, 1)
            XCTAssertEqual(fixture.output.requests.count, 1)
            XCTAssertEqual(fixture.output.requests.first?.target?.id, fixture.target.id)
            try await fixture.runtime.stop()
        }
    }

    func testExplicitCopyDoesNotRequireLocalTargetAdmission() async throws {
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.targetAvailable = false
        try await fixture.start()
        let execution = try fixture.runtime.service(SessionServices.execution)
        let intent = SessionIntent(input: .local, operation: .copy("Explicit owned copy"))
        try execution.start(intent)
        _ = try await execution.waitForCompletion(intent.id)
        guard case .clipboard(let text) = fixture.output.requests.first?.command else {
            return XCTFail("Explicit copy was refused")
        }
        XCTAssertEqual(text, "Explicit owned copy")
        XCTAssertEqual(fixture.output.requests.count, 1)
        XCTAssertTrue(fixture.screen.requests.isEmpty)
        XCTAssertTrue(fixture.recipe.requests.isEmpty)
        XCTAssertTrue(try fixture.runtime.service(DataServices.history).records.isEmpty)
        try await fixture.runtime.stop()
    }

    func testNativeSecureTargetFailureCannotBecomeScreenCommandAndOutput() async throws {
        guard NativeDeliveryKeys.isSecureInput else {
            throw XCTSkip("Secure input off; no unowned focused host capture permitted")
        }
        let fixture = try VoiceWorkflowFixture()
        defer { fixture.remove() }
        fixture.defaults.set(false, forKey: "useScreenContext")
        try await fixture.start()
        let native = PluginRuntime(catalog: try PluginCatalog([MacPlugins.target()]))
        try await native.start([PluginSelection("mac.target")])
        let runtime = fixture.runtime!
        let dependencies = VoiceWorkflowDependencies(
            settings: try runtime.service(DataServices.settings), credentials: try runtime.service(DataServices.credentials),
            configuration: nil, dictionary: try runtime.service(DataServices.dictionary),
            lexicons: try runtime.service(DataServices.lexicons), clients: try runtime.service(IntegrationServices.clients),
            files: fixture.files, access: try runtime.service(ModelServices.resourceAccess),
            speech: try runtime.service(SpeechServices.providers), generation: try runtime.service(GenerationServices.providers),
            recipes: try runtime.service(ModeServices.recipes), outputs: try runtime.service(SessionServices.outputs),
            preparation: try runtime.service(ProcessingServices.preparation), capture: fixture.capture,
            audioFiles: try runtime.service(AudioServices.files), evidence: fixture.evidence, output: fixture.output,
            targets: try native.service(MacServices.target), memory: nil, screen: fixture.screen,
            sounds: nil, correction: nil, log: NativeE2EDiagnostics())
        let driver = SessionDriver(workflows: VoiceWorkflowFactory(dependencies: dependencies, isReady: { true }),
            history: try runtime.service(DataServices.history), notifications: StateNotifications())
        let intent = SessionIntent(input: .text("Rewrite the selected synthetic text politely"), mode: .command)
        do {
            try driver.start(intent)
            _ = try await driver.waitForCompletion(intent.id)
        } catch {}
        XCTAssertTrue(fixture.screen.requests.isEmpty, "Secure native target refusal became an OCR/screenshot request")
        XCTAssertTrue(fixture.recipe.requests.isEmpty, "Secure native target refusal became generation")
        XCTAssertTrue(fixture.output.requests.isEmpty, "Secure native target refusal became an output effect")
        XCTAssertTrue(try runtime.service(DataServices.history).records.isEmpty)
        try NativeE2EUI.record("secure-native-session", ["screenRequests": fixture.screen.requests.count,
            "recipeRequests": fixture.recipe.requests.count, "outputRequests": fixture.output.requests.count,
            "nativeTarget": "production MacPlugins.target with current secure event input",
            "session": "production VoiceWorkflowFactory and SessionDriver",
            "screenGenerationOutput": "controlled fixtures; no OCR/network/host write performed"])
        await driver.close()
        try await native.stop()
        try await runtime.stop()
    }
}
