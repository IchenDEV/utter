import Foundation
import XCTest
import UtterContracts
@testable import UtterUpdates

final class UpdateConfigurationTests: XCTestCase {
    private let validKey = Data(repeating: 7, count: 32).base64EncodedString()
    private let feed = "https://example.com/appcast.xml"

    private func environment(
        bundle: Bool = true, adHoc: Bool = false, feed: String? = "https://example.com/appcast.xml", key: String? = nil
    ) -> UpdateEnvironment {
        UpdateEnvironment(isApplicationBundle: bundle, isAdHocSigned: adHoc, feedURL: feed, publicKey: key ?? validKey)
    }

    func testCompleteSignedBundleEnablesTheUpdater() {
        XCTAssertEqual(
            UpdateConfiguration.resolve(environment()),
            .enabled(UpdateConfiguration(feedURL: URL(string: feed)!, publicKey: validKey)))
    }

    func testBundleWithoutUpdateKeysIsInert() {
        let bare = UpdateEnvironment(isApplicationBundle: true, isAdHocSigned: false, feedURL: nil, publicKey: nil)
        XCTAssertEqual(UpdateConfiguration.resolve(bare), .unavailable(.missingFeed))
        XCTAssertEqual(UpdateConfiguration.resolve(environment(feed: "  ")), .unavailable(.missingFeed))
    }

    func testBareExecutableIsInert() {
        XCTAssertEqual(UpdateConfiguration.resolve(environment(bundle: false)), .unavailable(.notApplicationBundle))
    }

    func testAdHocSignedBuildIsInertEvenWithKeys() {
        XCTAssertEqual(UpdateConfiguration.resolve(environment(adHoc: true)), .unavailable(.adHocSigned))
    }

    func testMissingPublicKeyIsInert() {
        let noKey = UpdateEnvironment(isApplicationBundle: true, isAdHocSigned: false, feedURL: feed, publicKey: nil)
        XCTAssertEqual(UpdateConfiguration.resolve(noKey), .unavailable(.invalidPublicKey))
    }

    func testPublicKeyMustBeBase64OfThirtyTwoBytes() {
        XCTAssertEqual(UpdateConfiguration.resolve(environment(key: "not base64!")), .unavailable(.invalidPublicKey))
        let short = Data(repeating: 1, count: 31).base64EncodedString()
        XCTAssertEqual(UpdateConfiguration.resolve(environment(key: short)), .unavailable(.invalidPublicKey))
        let long = Data(repeating: 1, count: 33).base64EncodedString()
        XCTAssertEqual(UpdateConfiguration.resolve(environment(key: long)), .unavailable(.invalidPublicKey))
    }

    func testRemoteFeedMustUseHTTPS() {
        for insecure in ["http://example.com/appcast.xml", "ftp://example.com/appcast.xml", "file:///tmp/appcast.xml",
                         "example.com/appcast.xml", "https://"] {
            XCTAssertEqual(UpdateConfiguration.resolve(environment(feed: insecure)), .unavailable(.insecureFeed), insecure)
        }
    }

    func testLoopbackFeedMayUseHTTPForRehearsal() {
        for local in ["http://127.0.0.1:8080/appcast.xml", "http://localhost:8080/appcast.xml", "http://[::1]:8080/appcast.xml"] {
            guard case .enabled = UpdateConfiguration.resolve(environment(feed: local)) else {
                return XCTFail("expected loopback to be allowed: \(local)")
            }
        }
        XCTAssertEqual(
            UpdateConfiguration.resolve(environment(feed: "http://127.0.0.1.example.com/appcast.xml")),
            .unavailable(.insecureFeed))
    }

    func testGateOrderReportsTheFirstFailedPrecondition() {
        let everythingWrong = UpdateEnvironment(isApplicationBundle: false, isAdHocSigned: true, feedURL: "http://x", publicKey: "x")
        XCTAssertEqual(UpdateConfiguration.resolve(everythingWrong), .unavailable(.notApplicationBundle))
    }
}
