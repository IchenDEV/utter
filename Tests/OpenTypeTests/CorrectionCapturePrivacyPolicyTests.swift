import XCTest
@testable import OpenType

final class CorrectionCapturePrivacyPolicyTests: XCTestCase {
    func testBlocksTerminalAndPasswordManagerApps() {
        XCTAssertTrue(CorrectionCapturePrivacyPolicy.isBlocked(
            appText: "com.apple.Terminal Terminal",
            fieldText: "AXTextArea"
        ))
        XCTAssertTrue(CorrectionCapturePrivacyPolicy.isBlocked(
            appText: "com.1password.1password 1Password",
            fieldText: "AXTextField"
        ))
    }

    func testBlocksSecureAndAddressFields() {
        XCTAssertTrue(CorrectionCapturePrivacyPolicy.isBlocked(
            appText: "com.apple.Safari Safari",
            fieldText: "AXTextField Address and Search"
        ))
        XCTAssertTrue(CorrectionCapturePrivacyPolicy.isBlocked(
            appText: "com.example.app",
            fieldText: "AXSecureTextField password"
        ))
    }

    func testAllowsOrdinaryTextEditorFields() {
        XCTAssertFalse(CorrectionCapturePrivacyPolicy.isBlocked(
            appText: "com.apple.TextEdit TextEdit",
            fieldText: "AXTextArea document body"
        ))
    }
}
