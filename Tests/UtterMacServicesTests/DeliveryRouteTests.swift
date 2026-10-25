import XCTest
import UtterContracts
@testable import UtterMacServices

@MainActor
final class DeliveryRouteTests: XCTestCase {
    func testLogSummaryNamesDispositionConfirmationPathAndTarget() {
        let paste = DeliveryCompletion(disposition: .accepted, confirmation: .targetValue, path: .paste, target: .web)
        XCTAssertEqual(paste.logSummary,
                       "Delivery completed: accepted, confirmation: \(DeliveryConfirmation.targetValue.rawValue), path: paste, target: web")
        let native = DeliveryCompletion(disposition: .uncertain, confirmation: .none, path: .accessibility, target: .native)
        XCTAssertEqual(native.logSummary,
                       "Delivery completed: uncertain, confirmation: \(DeliveryConfirmation.none.rawValue), path: accessibility, target: native")
        let untouched = DeliveryCompletion(disposition: .notCommitted)
        XCTAssertTrue(untouched.logSummary.hasSuffix("path: none, target: native"))
    }

    func testLogSummaryNeverCarriesDictatedTextReasonOrAnchor() {
        let secret = "SECRET-DICTATION-4242"
        let completion = DeliveryCompletion(disposition: .accepted, reason: secret, anchor: SummaryAnchor(text: secret),
                                            confirmation: .targetValue, path: .paste, target: .web)
        XCTAssertFalse(completion.logSummary.contains(secret))
        XCTAssertFalse(completion.logSummary.contains("4242"))
    }

    func testKillSwitchIsOffUnlessTheHiddenDefaultIsTrue() throws {
        let suite = "UtterKillSwitch-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(DeliveryKillSwitch.webEditorPasteEnabled(defaults))
        defaults.set(true, forKey: "deliveryWebEditorPasteDisabled")
        XCTAssertFalse(DeliveryKillSwitch.webEditorPasteEnabled(defaults))
        defaults.set(false, forKey: "deliveryWebEditorPasteDisabled")
        XCTAssertTrue(DeliveryKillSwitch.webEditorPasteEnabled(defaults))
    }

    func testKillSwitchRestoresTheAccessibilityFirstPathForChromiumNodes() {
        let chromium = ["AXRole", "AXValue", "ChromeAXNodeId"]
        XCTAssertTrue(WebContentEditorSignature.classifies(attributeNames: chromium, enabled: true))
        XCTAssertFalse(WebContentEditorSignature.classifies(attributeNames: chromium, enabled: false))
        XCTAssertFalse(WebContentEditorSignature.classifies(attributeNames: ["AXRole"], enabled: true))
    }
}

@MainActor
private final class SummaryAnchor: OutputAnchor {
    let target: any OutputTargetLease = SummaryTarget()
    let text: String
    let range: NSRange
    let expiresAt = Date().addingTimeInterval(15)
    let isCurrent = true
    init(text: String) { self.text = text; range = NSRange(location: 0, length: (text as NSString).length) }
    func correctionSeed(context: InputContext) -> CorrectionCaptureSeed? { nil }
}

@MainActor
private final class SummaryTarget: OutputTargetLease {
    let id = UUID()
    let processIdentifier: Int32 = 1
    let context = InputContext(outputMode: .processed, inputLanguage: .english, source: .menuBar)
    let isValid = true
    let isCurrent = true
}
