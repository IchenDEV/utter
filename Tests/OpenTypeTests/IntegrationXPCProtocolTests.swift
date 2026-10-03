import Foundation
import ObjectiveC
import XCTest
@testable import OpenType

final class IntegrationXPCProtocolTests: XCTestCase {
    func testObjectiveCProtocolIdentitiesRemainCompatible() {
        XCTAssertEqual(NSStringFromProtocol(OpenTypeXPCProtocol.self), "OpenType.OpenTypeXPCProtocol")
        XCTAssertEqual(NSStringFromProtocol(OpenTypeXPCEventSink.self), "OpenType.OpenTypeXPCEventSink")
        XCTAssertEqual(String(cString: protocol_getName(OpenTypeXPCProtocol.self)), "_TtP8OpenType19OpenTypeXPCProtocol_")
        XCTAssertEqual(String(cString: protocol_getName(OpenTypeXPCEventSink.self)), "_TtP8OpenType20OpenTypeXPCEventSink_")
    }
}
