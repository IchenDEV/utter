import XCTest
@testable import UtterContracts

final class LocalModelReliabilityTests: XCTestCase {
    func testActualContextMetadataAndOutputReservationAreRequiredBeforeInference() throws {
        let limit = try LocalGenerationBudget.contextLimit(configuration: Data(#"{"text_config":{"max_position_embeddings":4096}}"#.utf8))
        XCTAssertEqual(limit, 4096)
        XCTAssertTrue(LocalGenerationBudget.allows(inputTokens: 3328, outputTokens: 768, contextLimit: limit))
        XCTAssertFalse(LocalGenerationBudget.allows(inputTokens: 3329, outputTokens: 768, contextLimit: limit))
        XCTAssertFalse(LocalGenerationBudget.allows(inputTokens: 1, outputTokens: Int.max, contextLimit: limit))
        XCTAssertThrowsError(try LocalGenerationBudget.contextLimit(configuration: Data(#"{"max_position_embeddings":0}"#.utf8)))
    }

    func testDecoderDimensionsMatchTheInstalledTokenizerFamily() {
        XCTAssertTrue(WhisperModelDimensions.supports(repository: "openai/whisper-base", logits: 51865, encoder: 512))
        XCTAssertTrue(WhisperModelDimensions.supports(repository: "openai/whisper-base.en", logits: 51864, encoder: 512))
        XCTAssertTrue(WhisperModelDimensions.supports(repository: "openai/whisper-large-v3", logits: 51866, encoder: 1280))
        XCTAssertFalse(WhisperModelDimensions.supports(repository: "openai/whisper-base", logits: 51864, encoder: 512))
        XCTAssertFalse(WhisperModelDimensions.supports(repository: "openai/whisper-base", logits: 51865, encoder: 768))
        XCTAssertFalse(WhisperModelDimensions.supports(repository: "openai/whisper-large-v3", logits: 51865, encoder: 1280))
    }
}
