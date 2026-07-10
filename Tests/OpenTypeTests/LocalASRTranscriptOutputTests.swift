import XCTest
@testable import OpenType

/// The resident local ASR runner answers one JSON object per line:
/// {"text": …}, {"error": …}, or the {"ready": true} handshake.
/// These tests lock in that per-line contract.
final class LocalASRTranscriptOutputTests: XCTestCase {
    func testParsesTextResponseLine() {
        XCTAssertEqual(
            LocalASRServerResponse.parse(line: #"{"text":" 你好，OpenType。 "}"#),
            .text("你好，OpenType。")
        )
        XCTAssertEqual(
            LocalASRServerResponse.parse(
                line: #"{"text": "那个，我想问一下这个接口。", "language": "Chinese", "duration": 6.34}"#
            ),
            .text("那个，我想问一下这个接口。")
        )
    }

    func testParsesReadyHandshakeAndErrorLines() {
        XCTAssertEqual(LocalASRServerResponse.parse(line: #"{"ready": true}"#), .ready)
        XCTAssertEqual(
            LocalASRServerResponse.parse(line: #"{"error": "Audio file not found: /tmp/x.wav"}"#),
            .error("Audio file not found: /tmp/x.wav")
        )
    }

    func testSkipsStrayStdoutLines() {
        XCTAssertNil(LocalASRServerResponse.parse(line: "Loading local ASR model..."))
        XCTAssertNil(LocalASRServerResponse.parse(line: "Fetching 12 files: 100%"))
        XCTAssertNil(LocalASRServerResponse.parse(line: ""))
        XCTAssertNil(LocalASRServerResponse.parse(line: #"{"progress": 0.4}"#))
    }

    func testKeepsDictatedJSONInsideTextFieldVerbatim() {
        XCTAssertEqual(
            LocalASRServerResponse.parse(line: #"{"text":"配置里写 {\"key\": \"value\"} 就可以"}"#),
            .text(#"配置里写 {"key": "value"} 就可以"#)
        )
    }

    func testMapsNoSpeechPlaceholderToEmpty() {
        XCTAssertEqual(LocalASRServerResponse.parse(line: #"{"text":"（无）"}"#), .text(""))
    }
}
