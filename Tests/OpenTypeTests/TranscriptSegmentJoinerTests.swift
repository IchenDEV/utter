import XCTest
@testable import OpenType

final class TranscriptSegmentJoinerTests: XCTestCase {
    func testCJKLanguageJoinsChunkSegmentsWithoutSpaces() {
        XCTAssertEqual(
            TranscriptSegmentJoiner.joined(["你好", "世界"], language: "zh"),
            "你好世界"
        )
        XCTAssertEqual(
            TranscriptSegmentJoiner.joined(["こんにちは", "世界"], language: "ja"),
            "こんにちは世界"
        )
        XCTAssertEqual(
            TranscriptSegmentJoiner.joined(["안녕하세요", "세계"], language: "ko"),
            "안녕하세요세계"
        )
    }

    func testLatinLanguageKeepsSpaceBetweenChunkSegments() {
        XCTAssertEqual(
            TranscriptSegmentJoiner.joined(["hello", "world"], language: "en"),
            "hello world"
        )
    }

    func testAutoLanguageFallsBackToBoundaryCharacters() {
        XCTAssertEqual(
            TranscriptSegmentJoiner.joined(["你好", "世界"], language: nil),
            "你好世界"
        )
        XCTAssertEqual(
            TranscriptSegmentJoiner.joined(["hello", "world"], language: nil),
            "hello world"
        )
    }

    func testTrimsSegmentsAndDropsEmpties() {
        XCTAssertEqual(
            TranscriptSegmentJoiner.joined(["  你好 ", "", " 世界  "], language: "zh"),
            "你好世界"
        )
        XCTAssertEqual(TranscriptSegmentJoiner.joined([], language: "zh"), "")
        XCTAssertEqual(TranscriptSegmentJoiner.joined(["", "   "], language: "en"), "")
    }
}
