import UtterMediaContracts
import UtterPresentationContracts
import UtterData
import UtterModels
import UtterProcessing
import UtterMacServices
import UtterAudio
import UtterRemoteMic
import UtterSession
import UtterWhisper
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import UtterAppleSpeech
import UtterContracts
import Foundation
import XCTest
@testable import UtterPresentation

final class AppleSpeechAnalyzerIntegrationTests: XCTestCase {
    func testTranscribesBundledChineseSample() async throws {
        guard ProcessInfo.processInfo.environment["OPENTYPE_APPLE_SPEECH_INTEGRATION"] == "1" else {
            throw XCTSkip("Set OPENTYPE_APPLE_SPEECH_INTEGRATION=1 to run this integration test")
        }

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let audioURL = repository.appendingPathComponent("docs/assets/demos/zh-sample.m4a")
        let text = try await AppleSpeechAnalyzer.transcribe(
            audioURL: audioURL,
            locale: Locale(identifier: "zh-CN")
        )

        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
