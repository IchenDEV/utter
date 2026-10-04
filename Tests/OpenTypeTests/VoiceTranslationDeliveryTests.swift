import XCTest
import UtterContracts
import UtterData
import UtterSession

@MainActor
final class VoiceTranslationDeliveryTests: XCTestCase {
    func testMissingOrMismatchedLanguageProofPreservesTextWithoutOutputEffects() async throws {
        for mismatched in [false, true] {
            let fixture = try VoiceWorkflowFixture()
            defer { fixture.remove() }
            fixture.recipe.confirmsTranslation = mismatched
            fixture.recipe.translationProofTarget = .german
            try await fixture.start()
            let driver = try fixture.runtime.service(SessionServices.execution)
            let intent = SessionIntent(input: .text("Synthetic input"), mode: .translation(.english))
            try driver.start(intent)
            do { _ = try await driver.waitForCompletion(intent.id); XCTFail("Unverified translation was accepted") }
            catch { XCTAssertEqual(error as? IntegrationError, .operationFailed) }
            let result = driver.snapshot
            XCTAssertEqual(result.phase, .failed)
            XCTAssertEqual(result.deliveryStatus, .notDelivered)
            XCTAssertEqual(result.text, "Synthetic input Formatted.")
            XCTAssertEqual(result.error, L("translation.unverifiable"))
            XCTAssertTrue(fixture.output.requests.isEmpty)
            let record = try XCTUnwrap(fixture.runtime.service(DataServices.history).records.first)
            XCTAssertEqual(record.processedText, result.text)
            XCTAssertEqual(record.deliveryStatus, .notDelivered)
            XCTAssertEqual(try fixture.runtime.service(SessionServices.outputs).snapshot.recentText, "")
            try await fixture.runtime.stop()
        }
    }
}
