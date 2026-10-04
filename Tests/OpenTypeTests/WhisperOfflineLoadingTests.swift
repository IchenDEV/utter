import Foundation
import WhisperKit
import XCTest
@testable import UtterWhisper

final class WhisperOfflineLoadingTests: XCTestCase {
    func testMissingLocalTokenizerNeverEntersTheSDKHubLoader() async throws {
        let kit = try await OfflineWhisperKit(WhisperKitConfig(modelFolder: "/missing/local-whisper",
            verbose: false, prewarm: false, load: false, download: false))
        XCTAssertNil(kit.tokenizer)
        do { try await kit.loadTokenizerIfNeeded(); XCTFail("Missing tokenizer entered the SDK fallback") }
        catch let error as CocoaError { XCTAssertEqual(error.code, .fileReadCorruptFile) }
    }
}
