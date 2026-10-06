import XCTest

/// Physical-device checks for background voice standby. Fixed speech is played by scripts/test-ios-device-audio.py.
extension UtterSimulatorFlow {
    var settings: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.Preferences") }
    private var safari: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.mobilesafari") }
    var searchField: XCUIElement { settings.searchFields.firstMatch }

    func testDeviceStandbyKeyboardSpeech() throws {
        addTeardownBlock { self.settings.terminate(); self.app.activate(); self.tapIfPresent("voice.disable"); self.app.terminate() }
        launchDeviceRelease()
        try enableStandby()
        try openSettingsSearch()
        selectStandbyKeyboard()
        try dictateFixedSpeech()
    }

    /// Standby idles behind Safari for five minutes; the keyboard must still dictate afterwards without revisiting Utter.
    func testDeviceStandbyKeyboardSpeechAfterIdle() throws {
        addTeardownBlock { self.settings.terminate(); self.app.activate(); self.tapIfPresent("voice.disable"); self.app.terminate() }
        launchDeviceRelease()
        try enableStandby()
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 5))
        Thread.sleep(forTimeInterval: 300)
        try openSettingsSearch()
        selectStandbyKeyboard()
        try dictateFixedSpeech()
    }

    /// Another app's Picture in Picture replaces ours (as with Doubao and WeChat); the keyboard must say so and recover with one visit.
    func testDeviceStandbyDisplacedByVideoRecovers() throws {
        guard let fixture = ProcessInfo.processInfo.environment["UTTER_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_UTTER_FIXTURE_URL to the LAN fixture served by scripts/tests/ios-standby/serve-safari.py")
        }
        addTeardownBlock {
            self.settings.terminate(); self.app.activate(); self.tapIfPresent("voice.disable"); self.app.terminate()
        }
        launchDeviceRelease()
        try enableStandby()
        try playFixtureInPiP(fixture)
        parkVideoPiP()
        try openSettingsSearch()
        selectStandbyKeyboard(expectingLive: false)
        XCTAssertEqual(settings.staticTexts["keyboard.status"].value as? String, "standby_off")
        capture("Keyboard after another app's Picture in Picture replaced standby")
        settings.descendants(matching: .any)["keyboard.activate"].firstMatch.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Keyboard link must open Utter")
        waitForStandby("active")
        capture("Utter reactivated standby after the keyboard link")
        settings.activate()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        selectStandbyKeyboard()
        try dictateFixedSpeech()
    }

    func testDeviceKeyboardAppearanceAndVoiceOver() throws {
        let device = XCUIDevice.shared
        let originalAppearance = device.appearance
        let voiceOver = device.voiceOverService
        let originalVoiceOver = voiceOver.isEnabled
        addTeardownBlock {
            if !originalVoiceOver { try voiceOver.disable() }
            self.settings.terminate(); self.app.activate(); self.tapIfPresent("voice.disable"); self.app.terminate()
            device.appearance = originalAppearance
        }
        try voiceOver.disable()
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            device.appearance = appearance
            launchDeviceRelease()
            tapIfPresent("voice.disable")
            try openSettingsSearch()
            selectStandbyKeyboard(expectingLive: false)
            capture("Keyboard unavailable appearance \(appearance.rawValue)")
            XCTAssertTrue(settings.buttons["keyboard.delete"].isHittable)
            XCTAssertTrue(settings.buttons["keyboard.space"].isHittable)
            XCTAssertTrue(settings.buttons["keyboard.return"].isHittable)
            settings.buttons["keyboard.space"].tap()
            settings.buttons["keyboard.delete"].tap()
            settings.descendants(matching: .any)["keyboard.activate"].firstMatch.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            waitForStandby("active")
            settings.activate(); selectStandbyKeyboard()
            try dictateFixedSpeech()
        }
        try voiceOver.enable()
        settings.staticTexts["keyboard.status"].tap()
        var spoken: [String] = []
        for _ in 0..<50 {
            let speech = try voiceOver.moveForward()
            spoken.append(speech.utterance)
            print("KEYBOARD_VOICEOVER \(speech.utterance)")
            if spoken.contains(where: { $0.contains("Next keyboard") || $0.contains("切换键盘") }) { break }
        }
        XCTAssertTrue(spoken.contains { $0.contains("Record") || $0.contains("录音") })
        XCTAssertTrue(spoken.contains { $0.contains("Space") || $0.contains("空格") })
        XCTAssertTrue(spoken.contains { $0.contains("Next keyboard") || $0.contains("切换键盘") })
        capture("Keyboard real VoiceOver traversal")
        settings.buttons["keyboard.start"].tap(); settings.buttons["keyboard.start"].doubleTap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'recording'"), object: settings.staticTexts["keyboard.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 15), .completed)
        settings.buttons["keyboard.cancel"].tap(); settings.buttons["keyboard.cancel"].doubleTap()
        let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'cancelled'"), object: settings.staticTexts["keyboard.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 10), .completed)
        capture("Keyboard real VoiceOver recording cancellation")
        if !originalVoiceOver { try voiceOver.disable() }
        settings.buttons["keyboard.globe"].press(forDuration: 1)
        XCTAssertTrue(settings.tables["InputSwitcherTable"].waitForExistence(timeout: 5))
        capture("Keyboard native globe long press")
    }

    func enableStandby() throws {
        openProductPage("Voice")
        tapButton("voice.enable", down: true)
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "允许", "OK", "好"])).firstMatch
            XCTAssertTrue(allow.exists); allow.tap()
        }
        waitForStandby("active")
        capture("Physical standby active")
    }

    func testDeviceKeyboardReduceMotion() throws {
        try XCUIDevice.shared.voiceOverService.disable()
        launchDeviceRelease()
        try openAccessibilitySettings()
        let motion = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["Motion", "动态效果"])).firstMatch
        XCTAssertTrue(motion.waitForExistence(timeout: 5)); motion.tap()
        let reduce = settings.switches.matching(NSPredicate(format: "label CONTAINS 'Reduce Motion' OR label CONTAINS '减弱动态效果'")).firstMatch
        XCTAssertTrue(reduce.waitForExistence(timeout: 5))
        let original = reduce.value as? String
        addTeardownBlock {
            try self.openAccessibilitySettings()
            motion.tap()
            if reduce.value as? String != original { reduce.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            self.capture("Device Reduce Motion restored")
            self.settings.terminate(); self.app.activate(); self.tapIfPresent("voice.disable"); self.app.terminate()
        }
        if original == "0" { reduce.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        waitForValue(reduce, "1")
        capture("Device Reduce Motion enabled")
        app.activate(); try enableStandby()
        try openSettingsSearch(); selectStandbyKeyboard()
        settings.buttons["keyboard.start"].tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'recording'"), object: settings.staticTexts["keyboard.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 15), .completed)
        capture("Keyboard Reduce Motion recording frame one")
        Thread.sleep(forTimeInterval: 2)
        capture("Keyboard Reduce Motion recording frame two")
        settings.buttons["keyboard.cancel"].tap()
        let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'cancelled'"), object: settings.staticTexts["keyboard.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 10), .completed)
    }

    func waitForStandby(_ value: String) {
        let footer = app.staticTexts["voice.standby"]
        // A failed start reports its diagnostic in the value; stop waiting as soon as it appears.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR value BEGINSWITH 'failed'", value), object: footer)
        _ = XCTWaiter.wait(for: [ready], timeout: 120)
        XCTAssertEqual(footer.value as? String, value, "Standby must reach \(value)")
    }

    func openSettingsSearch() throws {
        settings.launch()
        for _ in 0..<4 where !searchField.exists {
            let back = settings.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Settings", "设置", "Apps", "App", "应用"])).firstMatch
            if back.exists { back.tap() } else { break }
        }
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Settings search field must be visible")
    }

    func selectStandbyKeyboard(expectingLive: Bool = true) {
        searchField.tap()
        if !settings.staticTexts["keyboard.status"].exists {
            let globe = settings.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一个键盘", "切换键盘"])).firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5))
            globe.press(forDuration: 1)
            let utter = settings.tables["InputSwitcherTable"].cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Utter")).firstMatch
            XCTAssertTrue(utter.waitForExistence(timeout: 5)); utter.tap()
        }
        XCTAssertTrue(settings.staticTexts["keyboard.status"].waitForExistence(timeout: 5))
        let target = expectingLive ? "keyboard.start" : "keyboard.activate"
        XCTAssertTrue(settings.descendants(matching: .any)[target].firstMatch.waitForExistence(timeout: 10), "Keyboard must show \(target)")
    }

    func dictateFixedSpeech(scrollResult: Bool = false, rejectAfterDocumentChange: Bool = false) throws {
        let field = searchField
        let original = field.value as? String ?? ""
        let before = original == field.placeholderValue ? "" : original
        capture("Keyboard ready for fixed speech")
        settings.buttons["keyboard.start"].tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'recording'"),
                                                  object: settings.staticTexts["keyboard.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 15), .completed, "Recording must start without leaving the host app")
        XCTAssertEqual(settings.state, .runningForeground)
        capture("Keyboard recording fixed speech")
        FileHandle.standardOutput.write(Data("UTTER_AUDIO_READY zh \(Date().timeIntervalSince1970)\n".utf8))
        Thread.sleep(forTimeInterval: 12)
        settings.buttons["keyboard.stop"].tap()
        capture("Keyboard immediately after stop request")
        // The text is written into the field while it is recognized; the dictation is final once undo is offered.
        XCTAssertTrue(settings.buttons["keyboard.undo"].waitForExistence(timeout: 100), "Dictation must finish into the host field")
        XCTAssertEqual(settings.state, .runningForeground)
        let value = field.value as? String ?? ""
        let recognized = String(value.dropFirst(before.count))
        print("DEVICE_STANDBY_RESULT \(recognized)")
        XCTAssertTrue(value.hasPrefix(before) && recognized.contains("公园") && recognized.contains("水"), recognized)
        capture("Real background speech streamed into Settings")
        if rejectAfterDocumentChange {
            settings.buttons["keyboard.space"].tap()
            XCTAssertFalse(settings.buttons["keyboard.undo"].exists, "Editing the document must end the dictation")
            XCTAssertEqual(field.value as? String, value + " ")
            capture("Keyboard offers no undo after a document edit")
            return
        }
        if scrollResult { capture("Keyboard with a long dictation in the field") }
        settings.buttons["keyboard.undo"].tap()
        let rewritten = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", value), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [rewritten], timeout: 5), .completed, "Undo must take the dictation back")
    }

    func tapIfPresent(_ id: String) {
        let button = app.buttons[id]
        if button.waitForExistence(timeout: 3) { button.tap() }
    }

    private func playFixtureInPiP(_ url: String) throws {
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        let tabs = safari.descendants(matching: .any).matching(NSPredicate(format:
            "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@", "TabBarTab?", "TabDocument?"))
        let existing = Set(tabs.allElementsBoundByIndex.compactMap(tabID))
        let active = safari.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "TabBarTab?isActive=true")).firstMatch
        var fixture = try XCTUnwrap(URLComponents(string: url))
        fixture.queryItems = (fixture.queryItems ?? []) + [URLQueryItem(name: "utter-test", value: UUID().uuidString)]
        XCUIDevice.shared.system.open(try XCTUnwrap(fixture.url))
        Thread.sleep(forTimeInterval: 3)
        let created = try XCTUnwrap(tabID(active))
        guard !existing.contains(created) else {
            XCTFail("The fixture needs its own tab; existing tabs are never edited")
            return
        }
        addTeardownBlock { self.closeFixtureTab(created) }
        let warning = safari.staticTexts["此连接不安全"].waitForExistence(timeout: 5)
        if warning {
            capture("Safari security warning awaiting manual user action")
            print("UTTER_BROWSER_USER_ACTION_REQUIRED")
        }
        guard safari.buttons["Play video"].waitForExistence(timeout: warning ? 120 : 30) else {
            XCTFail("Fixture did not load; Safari security warnings require manual user action")
            return
        }
        safari.buttons["Play video"].tap()
        Thread.sleep(forTimeInterval: 3)
        safari.buttons["Start video PiP"].tap()
        Thread.sleep(forTimeInterval: 3)
        let state = safari.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Video:'")).firstMatch.label
        XCTAssertTrue(state.contains("picture-in-picture") && state.contains("paused=false"), state)
        capture("External video Picture in Picture started")
    }

    /// The system video window starts at the top-left covering the Settings sidebar; park it by the right edge,
    /// clear of the sidebar (left) and the keyboard (bottom), before opening the host.
    private func parkVideoPiP() {
        guard let pip = safari.windows.allElementsBoundByIndex.first(where: { $0.frame.width < 500 }) else { return }
        let center = pip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = safari.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        center.press(forDuration: 0.6, thenDragTo: target)
        Thread.sleep(forTimeInterval: 0.5)
        capture("External video window parked by the right edge")
    }

    private func closeFixtureTab(_ id: String) {
        safari.activate()
        guard safari.wait(for: .runningForeground, timeout: 5) else { return }
        Thread.sleep(forTimeInterval: 1)
        let tab = safari.buttons.matching(NSPredicate(format: "identifier CONTAINS %@", "UUID=\(id)&")).firstMatch
        guard tab.exists else { return }
        if !tab.identifier.contains("isActive=true") { tab.tap() }
        if safari.buttons["Stop video"].exists { safari.buttons["Stop video"].tap() }
        let close = safari.buttons.matching(identifier: "CloseTabBarItemButton")
        if close.count == 1 { close.firstMatch.tap() }
    }

    private func tabID(_ tab: XCUIElement) -> String? {
        guard tab.identifier.contains("UUID=") else { return nil }
        return tab.identifier.components(separatedBy: "UUID=").last?.components(separatedBy: "&").first
    }
}
