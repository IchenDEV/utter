import XCTest
@testable import UtterRemoteMic

final class RemoteKeyMappingCodecTests: XCTestCase {
    private func dictionary(_ source: Any, _ destination: Any) -> [String: Any] {
        [RemoteKeyMappingCodec.sourceKey: source, RemoteKeyMappingCodec.destinationKey: destination]
    }

    func testAbsentPropertyMeansNoMapping() {
        XCTAssertEqual(RemoteKeyMappingCodec.decode(nil), [])
        XCTAssertEqual(RemoteKeyMappingCodec.decode([Any]()), [])
    }

    func testDecodesTheMeasuredHardwareValue() {
        let property: [Any] = [dictionary(NSNumber(value: UInt64(30_064_771_134)), NSNumber(value: 0))]
        XCTAssertEqual(RemoteKeyMappingCodec.decode(property), [RemoteKeyMappingPolicy.ours])
    }

    func testEncodeThenDecodeRoundTripsAndKeepsOrder() {
        let entries = [
            KeyMappingEntry(source: 0x7_0000_0039, destination: 0x7_0000_0029),
            RemoteKeyMappingPolicy.ours,
        ]
        XCTAssertEqual(RemoteKeyMappingCodec.decode(RemoteKeyMappingCodec.encode(entries) as NSArray), entries)
    }

    func testEncodedEntriesUseTheHIDKeyNames() {
        let encoded = RemoteKeyMappingCodec.encode([RemoteKeyMappingPolicy.ours])
        XCTAssertEqual(encoded.count, 1)
        XCTAssertEqual(encoded[0]["HIDKeyboardModifierMappingSrc"]?.uint64Value, 30_064_771_134)
        XCTAssertEqual(encoded[0]["HIDKeyboardModifierMappingDst"]?.uint64Value, 0)
    }

    func testAnythingItCannotRepresentIsUnreadableSoItIsNeverRewritten() {
        XCTAssertNil(RemoteKeyMappingCodec.decode("not a list"))
        XCTAssertNil(RemoteKeyMappingCodec.decode([dictionary("text", NSNumber(value: 0))]))
        XCTAssertNil(RemoteKeyMappingCodec.decode([dictionary(NSNumber(value: 1), NSNumber(value: 2)).merging(["Extra": 1]) { $1 }]))
        XCTAssertNil(RemoteKeyMappingCodec.decode([["HIDKeyboardModifierMappingSrc": NSNumber(value: 1)]]))
        XCTAssertNil(RemoteKeyMappingCodec.decode([dictionary(NSNumber(value: 1), NSNumber(value: 2)), "stray"]))
    }
}
