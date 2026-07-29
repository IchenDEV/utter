import XCTest
@testable import OpenType

final class ModelDownloadFailureMessageTests: XCTestCase {
    func testTimeoutMessageExplainsResumeBehavior() {
        XCTAssertEqual(
            ModelDownloadFailureMessage.userFacing(URLError(.timedOut)),
            L("model.download_failed_timeout")
        )
    }

    func testDiskSpaceMessageProvidesStorageAction() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        XCTAssertEqual(
            ModelDownloadFailureMessage.userFacing(error),
            L("model.download_failed_disk_space")
        )
    }

    func testWrappedNetworkErrorIsRecognized() {
        let error = NSError(
            domain: "Hub.Download",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: URLError(.networkConnectionLost)]
        )
        XCTAssertEqual(
            ModelDownloadFailureMessage.userFacing(error),
            L("model.download_failed_network")
        )
    }
}
