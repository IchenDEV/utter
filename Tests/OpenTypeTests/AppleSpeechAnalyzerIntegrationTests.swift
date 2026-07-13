import Foundation
import XCTest
@testable import OpenType

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
