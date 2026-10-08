import XCTest
import UtterContracts
@testable import UtterMacServices

final class HotkeyGestureControllerTests: XCTestCase {
    func testCaptureStartsImmediatelyAndGraceOnlyPromotesTheExistingCapture() {
        for delay in [999, 1000, 1001] {
            let fixture = GestureFixture()
            fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
            XCTAssertEqual(fixture.events, ["start:dictation"])
            let captureID = fixture.controller.captureID
            XCTAssertNotNil(captureID)
            fixture.time = .milliseconds(delay)
            fixture.controller.process(primaryPressed: true, translationModifierPressed: true)
            fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
            XCTAssertEqual(fixture.events, ["start:dictation", "promote"])
            XCTAssertEqual(fixture.promotions, [delay <= 1000 ? .chordClassification : .recording])
            XCTAssertEqual(fixture.controller.captureID, captureID)
            fixture.controller.process(primaryPressed: false, translationModifierPressed: false)
            XCTAssertEqual(fixture.events.last, "stop:translation")
            XCTAssertNil(fixture.controller.captureID)
        }
    }

    func testShiftBeforePrimaryAndRepeatedFlagsProduceOneTranslationCapture() {
        let fixture = GestureFixture()
        fixture.controller.process(primaryPressed: false, translationModifierPressed: true)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: true)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: true)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
        XCTAssertEqual(fixture.events, ["start:translation"])
        fixture.controller.process(primaryPressed: false, translationModifierPressed: false)
        fixture.controller.process(primaryPressed: false, translationModifierPressed: true)
        XCTAssertEqual(fixture.events, ["start:translation", "stop:translation"])
    }

    func testSystemCombinationCancelsTentativeCaptureAndSuppressesUntilRelease() {
        let fixture = GestureFixture()
        fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: false, systemCombination: true)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: true)
        fixture.controller.process(primaryPressed: false, translationModifierPressed: true)
        XCTAssertEqual(fixture.events, ["start:dictation", "cancel"])
        fixture.controller.process(primaryPressed: true, translationModifierPressed: true, systemCombination: true)
        fixture.controller.process(primaryPressed: false, translationModifierPressed: false)
        XCTAssertEqual(fixture.events, ["start:dictation", "cancel"])
        fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
        XCTAssertEqual(fixture.events.last, "start:dictation")
    }

    func testPhysicalKeysAndReleaseModeRemainFrozenDuringOnePress() {
        let fixture = GestureFixture()
        fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
        fixture.settings.hotkeyType = .option
        fixture.settings.activationMode = .toggle
        XCTAssertEqual(fixture.controller.keySettings.hotkeyType, .fn)
        fixture.controller.process(primaryPressed: false, translationModifierPressed: false)
        XCTAssertEqual(fixture.events, ["start:dictation", "stop:dictation"])
        XCTAssertEqual(fixture.controller.keySettings.hotkeyType, .option)
    }

    func testDoubleTapCanClassifyTheFirstTapWithoutStartingAnotherCapture() {
        let fixture = GestureFixture()
        fixture.settings.activationMode = .doubleTap
        fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: true)
        fixture.controller.process(primaryPressed: false, translationModifierPressed: true)
        fixture.time = .milliseconds(200)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: true)
        XCTAssertEqual(fixture.events, ["start:translation"])
    }

    func testExpiredChordCannotReclassifyATapWithoutAnActiveCapture() {
        let fixture = GestureFixture()
        fixture.settings.activationMode = .doubleTap
        fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
        fixture.time = .milliseconds(1001)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: true)
        fixture.controller.process(primaryPressed: false, translationModifierPressed: true)
        fixture.time = .milliseconds(1200)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: true)
        XCTAssertTrue(fixture.events.isEmpty)
    }

    func testCallbackWiringDoesNotRetainTheRetiredController() {
        var controller: HotkeyGestureController? = HotkeyGestureController(settings: { SettingsValues() },
            onStart: { _ in }, onStop: { _ in }, onPromote: { _ in true }, onCancel: {})
        weak var retired = controller
        controller?.process(primaryPressed: true, translationModifierPressed: false)
        controller = nil
        XCTAssertNil(retired)
    }

    func testToggleStopCannotBeTurnedIntoANewCaptureByLateShift() {
        let fixture = GestureFixture()
        fixture.settings.activationMode = .toggle
        fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
        fixture.controller.process(primaryPressed: false, translationModifierPressed: false)
        fixture.time = .milliseconds(100)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: true)
        XCTAssertEqual(fixture.events, ["start:dictation", "stop:dictation"])
    }

    func testRejectedPromotionAndResetDoNotGenerateASecondStartOrStop() {
        let fixture = GestureFixture()
        fixture.acceptsPromotion = false
        fixture.controller.process(primaryPressed: true, translationModifierPressed: false)
        fixture.controller.process(primaryPressed: true, translationModifierPressed: true)
        fixture.controller.reset()
        fixture.controller.reset()
        XCTAssertEqual(fixture.events, ["start:dictation", "promote", "cancel"])
    }
}

private final class GestureFixture {
    var time: Duration = .zero
    var settings = SettingsValues()
    var events: [String] = []
    var acceptsPromotion = true
    var promotions: [HotkeyPromotion] = []
    lazy var controller = HotkeyGestureController(settings: { [weak self] in self?.settings ?? SettingsValues() },
        onStart: { [weak self] in self?.events.append("start:\($0)") }, onStop: { [weak self] in self?.events.append("stop:\($0)") },
        onPromote: { [weak self] in self?.promotions.append($0); self?.events.append("promote"); return self?.acceptsPromotion ?? false },
        onCancel: { [weak self] in self?.events.append("cancel") }, now: { [weak self] in self?.time ?? .zero })
}
