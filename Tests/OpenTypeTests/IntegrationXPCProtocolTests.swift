import Foundation
import XCTest
@testable import OpenType

final class IntegrationXPCProtocolTests: XCTestCase {
    func testObjectiveCProtocolIdentitiesRemainCompatible() {
        XCTAssertEqual(NSStringFromProtocol(OpenTypeXPCProtocol.self), "_TtP8OpenType19OpenTypeXPCProtocol_")
        XCTAssertEqual(NSStringFromProtocol(OpenTypeXPCEventSink.self), "_TtP8OpenType20OpenTypeXPCEventSink_")
    }
}
