import XCTest

/// Re-grants what a reinstall wipes in the designated simulator: Full Access for the Utter keyboard.
/// Runs only when /tmp/utter-setup-simulator exists. Labels are the simulator's (Chinese) system labels.
extension UtterSimulatorFlow {
    func testSetupSimulatorPermissions() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/utter-setup-simulator"), "Only for preparing a simulator")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate(); settings.launch()
        func tap(_ element: XCUIElement, _ step: String) {
            for _ in 0..<2 where element.exists && !element.isHittable { settings.swipeDown() }
            for _ in 0..<6 where !element.isHittable { settings.swipeUp() }
            if !element.waitForExistence(timeout: 5) { print("SETUP \(step) missing:\n" + settings.debugDescription); XCTFail("\(step) not found"); return }
            element.tap()
        }
        tap(settings.buttons["com.apple.settings.general"], "general")
        tap(settings.buttons["com.apple.settings.general.keyboard"], "keyboard")
        tap(settings.cells["KEYBOARDS"], "keyboards")
        capture("Setup keyboards")
        tap(settings.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Utter")).firstMatch, "utter")
        capture("Setup utter keyboard")
        let toggle = settings.switches.matching(NSPredicate(format: "label CONTAINS %@", "完全访问")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 2)
            capture("Setup alert")
            print("SETUP alert:\n" + settings.alerts.debugDescription)
            let allow = settings.alerts.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "允许", "Allow")).firstMatch
            if allow.waitForExistence(timeout: 5) { allow.tap() }
        }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(toggle.value as? String, "1")
        capture("Setup full access on")
    }
}
