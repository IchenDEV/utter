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
    func testDeviceKeyboardDocumentLifecycle() throws {
        let device = XCUIDevice.shared
        let originalAppearance = device.appearance
        try device.voiceOverService.disable()
        addTeardownBlock {
            self.settings.terminate(); self.app.activate(); self.tapIfPresent("voice.disable"); self.app.terminate()
            device.appearance = originalAppearance
        }
        launchDeviceRelease()
        try enableStandby()
        for index in 0..<10 {
            device.appearance = index.isMultiple(of: 2) ? .light : .dark
            app.activate(); waitForStandby("active")
            settings.activate()
            try openSettingsSearch(); selectStandbyKeyboard()
            capture("Keyboard document host return \(index)")
            for id in ["delete", "space", "return", "globe"] {
                XCTAssertTrue(settings.buttons["keyboard.\(id)"].isHittable)
            }
            settings.buttons["keyboard.space"].tap(); settings.buttons["keyboard.delete"].tap()
            settings.terminate()
            try openSettingsSearch(); selectStandbyKeyboard()
            capture("Keyboard document host restart \(index)")
        }
        try dictateFixedSpeech()
        try dictateFixedSpeech(rejectAfterDocumentChange: true)
    }

    func testDeviceKeyboardMaximumText() throws {
        try XCUIDevice.shared.voiceOverService.disable()
        launchDeviceRelease()
        tapIfPresent("voice.disable")
        try openLargerTextSettings()
        let larger = settings.switches["LARGER_DYNAMIC_TYPE_SWITCH"]
        let originalLarge = larger.value as? String
        let originalSize = try XCTUnwrap(Float((settings.sliders.firstMatch.value as? String ?? "").replacingOccurrences(of: "%", with: ""))) / 100
        addTeardownBlock {
            if !larger.exists { try self.openLargerTextSettings() }
            if larger.value as? String != originalLarge { larger.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            self.settings.sliders.firstMatch.adjust(toNormalizedSliderPosition: CGFloat(originalSize))
            self.capture("Device text size restored")
            self.settings.terminate(); self.app.activate()
            if self.app.buttons["voice.disable"].exists { self.app.buttons["voice.disable"].tap() }
            self.app.terminate()
        }
        if originalLarge == "0" { larger.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        waitForValue(larger, "1")
        let size = settings.sliders.firstMatch
        for _ in 0..<3 where size.value as? String != "100%" { size.adjust(toNormalizedSliderPosition: 1) }
        XCTAssertEqual(size.value as? String, "100%", "Accessibility text must reach the actual maximum")
        capture("Device maximum accessibility text selected")
        selectStandbyKeyboard(expectingLive: false)
        capture("Keyboard maximum accessibility text")
        for id in ["delete", "space", "return", "globe"] {
            let key = settings.buttons["keyboard.\(id)"]
            XCTAssertTrue(key.isHittable); XCTAssertGreaterThanOrEqual(key.frame.height, 44)
        }
        settings.scrollViews.containing(.staticText, identifier: "keyboard.status").firstMatch.swipeUp()
        XCTAssertTrue(settings.descendants(matching: .any)["keyboard.activate"].firstMatch.isHittable)
        capture("Keyboard maximum text scrolled to activation")
        settings.descendants(matching: .any)["keyboard.activate"].firstMatch.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10)); waitForStandby("active")
        settings.activate(); selectStandbyKeyboard()
        try dictateFixedSpeech(scrollResult: true)
    }

    private func openLargerTextSettings() throws {
        try openAccessibilitySettings()
        let display = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["Display & Text Size", "显示与文字大小"])).firstMatch
        XCTAssertTrue(display.waitForExistence(timeout: 5)); display.tap()
        let larger = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["Larger Text", "更大字体"])).firstMatch
        XCTAssertTrue(larger.waitForExistence(timeout: 5)); larger.tap()
    }

    func openAccessibilitySettings() throws {
        try openSettingsSearch()
        let clear = searchField.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'clear' OR label CONTAINS '清除'")).firstMatch
        if clear.exists { clear.tap() }
        let suggestion = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["Accessibility", "无障碍"])).firstMatch
        if suggestion.isHittable { suggestion.tap() }
        else {
            let general = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["General", "通用"])).allElementsBoundByIndex.first { $0.frame.minX > 300 }
            general?.tap()
            let accessibility = settings.buttons["com.apple.settings.accessibility"]
            let sidebar = settings.collectionViews["com.apple.settings.sidebar.collectionView"]
            for _ in 0..<12 where !accessibility.isHittable { sidebar.swipeUp() }
            XCTAssertTrue(accessibility.isHittable); accessibility.tap()
        }
    }

}
