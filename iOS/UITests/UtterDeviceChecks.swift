import XCTest
import UIKit

extension UtterSimulatorFlow {
    func launchDeviceRelease(language: String = "en", largeText: Bool = false) {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertFalse(app.buttons["diagnostic.enable"].exists)
    }

    func testDeviceReleaseKeyboardEditing() {
        launchDeviceRelease()
        let field = app.textFields["field.first"]
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown] {
            XCUIDevice.shared.orientation = orientation
            reveal(field); field.tap(); selectUtterKeyboard()
            XCTAssertFalse(app.buttons["keyboard.start"].exists)
            XCTAssertFalse(app.buttons["keyboard.stop"].exists)
            let globe = app.buttons["keyboard.globe"]
            XCTAssertTrue(globe.isHittable)
            app.buttons["keyboard.space"].tap(); waitForValue(field, " ")
            app.buttons["keyboard.delete"].tap()
            XCTAssertTrue(["", "First field"].contains(field.value as? String ?? ""))
            capture("Release keyboard orientation \(orientation.rawValue)")
            app.buttons["keyboard.return"].tap()
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["keyboard.return"])
            waitForExpectations(timeout: 5)
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testDeviceChineseAndLargeText() {
        for language in ["en", "zh-Hans"] {
            launchDeviceRelease(language: language, largeText: true)
            capture("Release large text \(language) voice")
            let field = app.textFields["field.first"]
            reveal(field); field.tap(); selectUtterKeyboard()
            XCTAssertTrue(app.buttons["keyboard.space"].isHittable)
            XCTAssertTrue(app.buttons["keyboard.globe"].isHittable)
            capture("Release large text \(language) keyboard")
            app.buttons["keyboard.return"].tap()
            let dictionary = app.buttons["dictionary.open"]
            reveal(dictionary); dictionary.tap()
            XCTAssertTrue(app.textFields["dictionary.original"].waitForExistence(timeout: 5))
            capture("Release large text \(language) dictionary")
        }
    }

    func testDeviceSettingsAndPrivacy() throws {
        launchDeviceRelease()
        openProductPage("Settings")
        for (id, options) in [("voice.language", ["Mandarin", "English"]), ("settings.duration", ["30 seconds", "60 seconds", "120 seconds"])] {
            let picker = app.buttons[id]
            reveal(picker, down: true)
            let original = try XCTUnwrap(options.first { picker.label.contains($0) || (picker.value as? String) == $0 })
            addTeardownBlock {
                self.app.terminate(); self.app.launch(); self.openProductPage("Settings")
                self.reveal(picker, down: true)
                picker.tap(); self.app.buttons[original].firstMatch.tap()
            }
            let changed = try XCTUnwrap(options.first { $0 != original })
            picker.tap(); app.buttons[changed].firstMatch.tap()
            app.terminate(); app.launch(); openProductPage("Settings")
            reveal(picker, down: true)
            XCTAssertTrue(picker.label.contains(changed) || (picker.value as? String) == changed)
            picker.tap(); app.buttons[original].firstMatch.tap()
        }
        let sounds = app.switches["settings.sounds"]
        reveal(sounds)
        let original = try XCTUnwrap(sounds.value as? String)
        addTeardownBlock {
            self.app.terminate(); self.app.launch(); self.openProductPage("Settings"); self.reveal(sounds)
            if sounds.value as? String != original { sounds.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        }
        sounds.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.terminate(); app.launch(); openProductPage("Settings"); reveal(sounds)
        XCTAssertEqual(sounds.value as? String, original == "1" ? "0" : "1")
        sounds.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForValue(sounds, original)
        tapButton("voice.clear_data")
        XCTAssertTrue(app.buttons["voice.clear_confirm"].waitForExistence(timeout: 3))
        capture("Clear local data requires explicit confirmation")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap() } else { app.navigationBars.firstMatch.tap() }
        XCTAssertFalse(app.buttons["voice.clear_confirm"].exists)
        openProductPage("Voice")
        tapButton("voice.settings")
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.Preferences").wait(for: .runningForeground, timeout: 5))
        capture("Release system permissions entry")
        app.activate()
    }

    func testDeviceVoiceAccessibility() throws { try auditDevicePage("Voice") }
    func testDeviceModelsAccessibility() throws { try auditDevicePage("Models") }
    func testDeviceSettingsAccessibility() throws { try auditDevicePage("Settings") }

    func testDeviceMicrophonePermissionRecovery() throws {
        launchDeviceRelease()
        tapButton("voice.settings")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5))
        let microphone = settings.switches.matching(NSPredicate(format: "label CONTAINS %@", "麦克风")).firstMatch
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        guard microphone.value as? String == "1" else { throw XCTSkip("This recovery check preserves the existing denied permission") }
        addTeardownBlock {
            self.app.launch(); self.openProductPage("Voice"); self.tapButton("voice.settings")
            XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5))
            XCTAssertTrue(microphone.waitForExistence(timeout: 5))
            if microphone.value as? String != "1" { microphone.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            self.waitForValue(microphone, "1")
            self.capture("Microphone permission restored")
            self.app.activate(); self.app.terminate()
        }
        microphone.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); waitForValue(microphone, "0")
        app.activate()
        tapButton("voice.enable", down: true); waitForPhase("failed")
        XCTAssertTrue(app.staticTexts["voice.status"].label.contains("Microphone access is off"))
        XCTAssertFalse(app.buttons["voice.record"].exists)
        capture("Real denied microphone blocks recording")
        tapButton("voice.settings")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5))
        microphone.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); waitForValue(microphone, "1")
        app.activate()
        tapButton("voice.enable", down: true); waitForPhase("ready")
        tapButton("voice.disable"); waitForPhase("disabled")
        capture("Real microphone permission recovery")
    }

    private func auditDevicePage(_ page: String) throws {
        launchDeviceRelease(); openProductPage(page)
        capture("Release \(page) before native audit")
        continueAfterFailure = true
        try app.performAccessibilityAudit { issue in
            print("Device accessibility \(page): \(issue.auditType.rawValue) \(issue.element?.debugDescription ?? "unresolved element")")
            self.capture("Release \(page) issue \(issue.auditType.rawValue)")
            return false
        }
    }

    func testDeviceLaunchPerformance() {
        app.terminate()
        app.launchArguments = []
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
            app.terminate()
        }
    }

    func testDeviceLargeSidebarAndNormalLaunch() {
        launchDeviceRelease(largeText: true)
        let voice = app.descendants(matching: .any).matching(identifier: "tab.voice").firstMatch
        if !voice.isHittable { app.buttons["Show Sidebar"].firstMatch.tap() }
        for page in ["voice", "models", "settings"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "tab.\(page)").firstMatch.isHittable)
        }
        capture("Maximum text sidebar labels")
        app.terminate()
        app.launchArguments = []
        app.launch()
        waitForPhase("disabled")
        XCTAssertFalse(app.buttons["diagnostic.enable"].exists)
        capture("Restored normal Release launch without test arguments")
    }
}
