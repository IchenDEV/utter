import XCTest
import UtterContracts
import UtterModels

final class ModelPreloadPolicyTests: XCTestCase {
    func testStartupPreloadPolicyLoadsOnlyWhisperSpeechModel() {
        XCTAssertTrue(ModelPreloadPolicy.speech(
            enabled: true, engine: .whisper, installed: true
        ))
        XCTAssertFalse(ModelPreloadPolicy.speech(
            enabled: true, engine: .whisper, installed: false
        ))
        for engine in [SpeechEngineType.apple, .volc, .qwen3] {
            XCTAssertFalse(ModelPreloadPolicy.speech(
                enabled: true, engine: engine, installed: true
            ))
        }
        XCTAssertFalse(ModelPreloadPolicy.speech(
            enabled: false, engine: .whisper, installed: true
        ))
    }

    func testStartupPreloadPolicyLoadsOnlyDownloadedLocalFormattingModelWithID() {
        XCTAssertTrue(ModelPreloadPolicy.text(
            enabled: true,
            remote: false,
            modelID: "mlx-community/Qwen3.5-2B-4bit",
            installed: true
        ))
        XCTAssertFalse(ModelPreloadPolicy.text(
            enabled: true,
            remote: false,
            modelID: "mlx-community/Qwen3.5-2B-4bit",
            installed: false
        ))
        XCTAssertFalse(ModelPreloadPolicy.text(
            enabled: true,
            remote: true,
            modelID: "gpt-4.1-mini",
            installed: true
        ))
        XCTAssertFalse(ModelPreloadPolicy.text(
            enabled: true,
            remote: false,
            modelID: "  ",
            installed: true
        ))
        XCTAssertFalse(ModelPreloadPolicy.text(
            enabled: false,
            remote: false,
            modelID: "mlx-community/Qwen3.5-2B-4bit",
            installed: true
        ))
    }

}
