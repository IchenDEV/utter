import UtterMediaContracts
import UtterData
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
import UtterPresentationContracts
import UtterContracts
import Foundation
import XCTest
@testable import UtterPresentation

final class ScreenContextModeTests: XCTestCase {
    func testCasesAreStable() {
        XCTAssertEqual(ScreenContextMode.allCases.map(\.rawValue), [
            "ocr", "multimodal",
        ])
    }

    func testDefaultsAndPersists() {
        let suiteName = "OpenTypeTests.ScreenContextMode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppSettings(defaults: defaults).screenContextMode, .ocr)

        defaults.set(ScreenContextMode.multimodal.rawValue, forKey: "screenContextMode")
        XCTAssertEqual(AppSettings(defaults: defaults).screenContextMode, .multimodal)
    }

    func testFallsBackToOCRWhenImageContextIsUnavailable() {
        XCTAssertEqual(ScreenContextMode.effectiveCaptureMode(
            preference: .multimodal,
            useRemoteLLM: false,
            modelID: "mlx-community/Qwen3.5-2B-4bit"
        ), .ocr)
        XCTAssertEqual(ScreenContextMode.effectiveCaptureMode(
            preference: .multimodal,
            useRemoteLLM: true,
            modelID: "mlx-community/gemma-4-e2b-it-4bit"
        ), .ocr)
        XCTAssertEqual(ScreenContextMode.effectiveCaptureMode(
            preference: .multimodal,
            useRemoteLLM: false,
            modelID: "mlx-community/gemma-4-e2b-it-4bit"
        ), .multimodal)
        XCTAssertEqual(ScreenContextMode.effectiveCaptureMode(
            preference: .multimodal,
            useRemoteLLM: false,
            modelID: "mlx-community/gemma4_unified"
        ), .multimodal)
    }
}
