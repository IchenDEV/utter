import UtterContracts
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
import UtterAppleSpeech
import UtterMLX
import UtterANE
import UtterRemoteInference
import UtterIngress
import Foundation
import ObjectiveC
import XCTest
@testable import UtterPresentation

final class IntegrationXPCProtocolTests: XCTestCase {
    func testObjectiveCProtocolIdentitiesRemainCompatible() {
        XCTAssertEqual(NSStringFromProtocol(OpenTypeXPCProtocol.self), "OpenTypeXPCProtocol")
        XCTAssertEqual(NSStringFromProtocol(OpenTypeXPCEventSink.self), "OpenTypeXPCEventSink")
        XCTAssertEqual(String(cString: protocol_getName(OpenTypeXPCProtocol.self)), "OpenTypeXPCProtocol")
        XCTAssertEqual(String(cString: protocol_getName(OpenTypeXPCEventSink.self)), "OpenTypeXPCEventSink")
    }
}
