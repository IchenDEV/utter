import Foundation
import ObjectiveC
import XCTest
@testable import OpenType

final class IntegrationXPCProtocolTests: XCTestCase {
    func testObjectiveCProtocolIdentitiesRemainCompatible() {
        XCTAssertEqual(NSStringFromProtocol(OpenTypeXPCProtocol.self), "OpenType.OpenTypeXPCProtocol")
        XCTAssertEqual(NSStringFromProtocol(OpenTypeXPCEventSink.self), "OpenType.OpenTypeXPCEventSink")
        XCTAssertEqual(String(cString: protocol_getName(OpenTypeXPCProtocol.self)), "OpenType.OpenTypeXPCProtocol")
        XCTAssertEqual(String(cString: protocol_getName(OpenTypeXPCEventSink.self)), "OpenType.OpenTypeXPCEventSink")
    }
}
