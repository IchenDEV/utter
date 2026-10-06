import XCTest

/// Physical-device checks for background voice standby. Fixed speech is played by scripts/test-ios-device-audio.py.
extension UtterSimulatorFlow {
    private var settings: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.Preferences") }
    private var safari: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.mobilesafari") }
    private var searchField: XCUIElement { settings.searchFields.firstMatch }

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
        var tab: String?
        addTeardownBlock {
            if let tab { self.closeFixtureTab(tab) }
            self.settings.terminate(); self.app.activate(); self.tapIfPresent("voice.disable"); self.app.terminate()
        }
        launchDeviceRelease()
        try enableStandby()
        tab = try playFixtureInPiP(fixture)
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

    private func enableStandby() throws {
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

    private func waitForStandby(_ value: String) {
        let footer = app.staticTexts["voice.standby"]
        // A failed start reports its diagnostic in the value; stop waiting as soon as it appears.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR value BEGINSWITH 'failed'", value), object: footer)
        _ = XCTWaiter.wait(for: [ready], timeout: 120)
        XCTAssertEqual(footer.value as? String, value, "Standby must reach \(value)")
    }

    private func openSettingsSearch() throws {
        settings.launch()
        for _ in 0..<4 where !searchField.exists {
            let back = settings.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Settings", "设置", "Apps", "App", "应用"])).firstMatch
            if back.exists { back.tap() } else { break }
        }
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Settings search field must be visible")
    }

    private func selectStandbyKeyboard(expectingLive: Bool = true) {
        searchField.tap()
        if !settings.staticTexts["keyboard.status"].exists {
            let globe = settings.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一个键盘"])).firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5))
            globe.press(forDuration: 1)
            let utter = settings.tables["InputSwitcherTable"].cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Utter")).firstMatch
            XCTAssertTrue(utter.waitForExistence(timeout: 5)); utter.tap()
        }
        XCTAssertTrue(settings.staticTexts["keyboard.status"].waitForExistence(timeout: 5))
        let target = expectingLive ? "keyboard.start" : "keyboard.activate"
        XCTAssertTrue(settings.descendants(matching: .any)[target].firstMatch.waitForExistence(timeout: 10), "Keyboard must show \(target)")
    }

    private func dictateFixedSpeech() throws {
        let field = searchField
        let original = field.value as? String ?? ""
        let before = original == field.placeholderValue ? "" : original
        settings.buttons["keyboard.start"].tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'recording'"),
                                                  object: settings.staticTexts["keyboard.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 15), .completed, "Recording must start without leaving the host app")
        XCTAssertEqual(settings.state, .runningForeground)
        FileHandle.standardOutput.write(Data("UTTER_AUDIO_READY zh \(Date().timeIntervalSince1970)\n".utf8))
        Thread.sleep(forTimeInterval: 12)
        settings.buttons["keyboard.stop"].tap()
        XCTAssertTrue(settings.buttons["keyboard.insert"].waitForExistence(timeout: 100))
        XCTAssertEqual(settings.state, .runningForeground)
        let recognized = settings.staticTexts["keyboard.result"].label
        print("DEVICE_STANDBY_RESULT \(recognized)")
        XCTAssertTrue(recognized.contains("公园") && recognized.contains("水"))
        settings.buttons["keyboard.insert"].tap()
        capture("Real background speech inserted into Settings")
        let inserted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", before + recognized), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [inserted], timeout: 5), .completed)
        XCTAssertFalse(settings.buttons["keyboard.insert"].exists, "A result must be inserted once")
    }

    private func tapIfPresent(_ id: String) {
        let button = app.buttons[id]
        if button.waitForExistence(timeout: 3) { button.tap() }
    }

    private func playFixtureInPiP(_ url: String) throws -> String {
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        let tabs = safari.descendants(matching: .any).matching(NSPredicate(format:
            "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@", "TabBarTab?", "TabDocument?"))
        let existing = Set(tabs.allElementsBoundByIndex.compactMap(tabID))
        let active = safari.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "TabBarTab?isActive=true")).firstMatch
        for _ in 0..<2 {
            safari.buttons["NewTabButton"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1)
            if active.exists, let created = tabID(active), !existing.contains(created) { break }
        }
        let created = try XCTUnwrap(tabID(active))
        XCTAssertFalse(existing.contains(created), "The fixture needs its own tab; existing tabs are never edited")
        active.textFields.firstMatch.tap()
        safari.typeText(url + "\n")
        Thread.sleep(forTimeInterval: 3)
        if safari.staticTexts["此连接不安全"].waitForExistence(timeout: 5), safari.buttons["继续"].exists { safari.buttons["继续"].tap() }
        XCTAssertTrue(safari.buttons["Play video"].waitForExistence(timeout: 30))
        safari.buttons["Play video"].tap()
        Thread.sleep(forTimeInterval: 3)
        safari.buttons["Start video PiP"].tap()
        Thread.sleep(forTimeInterval: 3)
        let state = safari.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Video:'")).firstMatch.label
        XCTAssertTrue(state.contains("picture-in-picture") && state.contains("paused=false"), state)
        capture("External video Picture in Picture started")
        return created
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
