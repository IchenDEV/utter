import XCTest

final class UtterSimulatorFlow: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--bridge-diagnostic", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testSessionFinishCancelAndDisable() {
        activateDiagnostic()
        tapButton("voice.record")
        waitForPhase("recording")
        tapButton("voice.stop")
        waitForPhase("result")
        reveal(app.staticTexts["Utter bridge sample"])
        XCTAssertTrue(app.staticTexts["Utter bridge sample"].exists)
        capture("Session result, synthetic text")
        tapButton("voice.record", down: true)
        waitForPhase("recording")
        tapButton("voice.cancel")
        waitForPhase("cancelled")
        XCTAssertFalse(app.staticTexts["Utter bridge sample"].exists)
        tapButton("voice.disable")
        waitForPhase("disabled")
        XCTAssertFalse(app.buttons["voice.record"].exists)
    }

    func testDeniedMicrophoneDoesNotEnableRecording() {
        tapButton("voice.enable")
        waitForPhase("failed")
        XCTAssertEqual(app.staticTexts["voice.status"].label, "Microphone access is off. Allow it in Utter’s settings.")
        XCTAssertFalse(app.buttons["voice.record"].exists)
        capture("Microphone denied, recording unavailable")
    }

    func testDiscardAndClearLocalData() {
        activateDiagnostic()
        tapButton("voice.record")
        waitForPhase("recording")
        tapButton("voice.stop")
        waitForPhase("result")
        let discard = app.buttons["voice.discard"]
        reveal(discard)
        discard.tap()
        waitForPhase("ready")
        XCTAssertFalse(app.staticTexts["Utter bridge sample"].exists)
        openProductPage("Settings")
        tapButton("voice.clear_data")
        app.buttons["voice.clear_confirm"].firstMatch.tap()
        openProductPage("Voice")
        waitForPhase("disabled")
        XCTAssertFalse(app.buttons["voice.record"].exists)
        capture("Local result discarded and runtime disabled after clear")
    }

    func testDictionaryReplacementAndDeletion() {
        clearTestData()
        activateDiagnostic()
        tapButton("dictionary.open")
        app.textFields["dictionary.original"].tap()
        app.textFields["dictionary.original"].typeText("Utter bridge sample")
        app.textFields["dictionary.replacement"].tap()
        app.textFields["dictionary.replacement"].typeText("Simulator preferred text")
        tapButton("dictionary.add")
        let entry = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "dictionary.entry.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        tapButton("voice.record", down: true)
        waitForPhase("recording")
        tapButton("voice.stop")
        waitForPhase("result")
        reveal(app.staticTexts["Simulator preferred text"])
        XCTAssertTrue(app.staticTexts["Simulator preferred text"].exists)
        capture("Real dictionary replacement in shared Session")
        tapButton("dictionary.open")
        reveal(entry); entry.swipeLeft()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dictionary.delete.")).firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: entry)
        waitForExpectations(timeout: 5)
        app.navigationBars.buttons.firstMatch.tap()
        clearTestData()
    }

    func testCopyResultAndOpenSettings() {
        activateDiagnostic()
        tapButton("voice.record")
        waitForPhase("recording")
        tapButton("voice.stop")
        waitForPhase("result")
        tapButton("voice.copy")
        let field = app.textFields["field.first"]
        reveal(field); field.tap(); field.press(forDuration: 1)
        let labels = ["Paste", "粘贴"]
        let paste = app.menuItems.matching(NSPredicate(format: "label IN %@", labels)).firstMatch.exists
            ? app.menuItems.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
            : app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        waitForValue(field, "Utter bridge sample")
        app.navigationBars.firstMatch.tap()
        tapButton("voice.settings", down: true)
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5))
        app.activate()
        capture("Copied result pasted into real host field")
    }

    private func clearTestData() {
        openProductPage("Settings")
        tapButton("voice.clear_data")
        app.buttons["voice.clear_confirm"].firstMatch.tap()
        openProductPage("Voice")
        waitForPhase("disabled")
    }

    func selectUtterKeyboard() {
        if !app.staticTexts["keyboard.status"].waitForExistence(timeout: 3) {
            let selector = app.buttons["Next keyboard"].firstMatch
            XCTAssertTrue(selector.waitForExistence(timeout: 3))
            selector.press(forDuration: 1)
            let utter = app.tables["InputSwitcherTable"].cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Utter,")).firstMatch
            XCTAssertTrue(utter.waitForExistence(timeout: 3))
            utter.tap()
        }
    }

    func startKeyboardSession() {
        XCTAssertTrue(app.buttons["keyboard.start"].waitForExistence(timeout: 5))
        app.buttons["keyboard.start"].tap()
        expectation(for: NSPredicate(format: "value == %@", "recording"), evaluatedWith: app.staticTexts["keyboard.status"])
        waitForExpectations(timeout: 15)
    }

    func activateSimulatorHost(arguments: [String] = []) {
        app.terminate()
        app.launchArguments.append("--simulator-bridge-host")
        app.launchArguments.append(contentsOf: arguments)
        app.launch()
        activateDiagnostic()
    }

    func waitForValue(_ element: XCUIElement, _ value: String) {
        expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    func activateDiagnostic() {
        let enable = app.buttons["diagnostic.enable"]
        reveal(enable)
        XCTAssertTrue(enable.waitForExistence(timeout: 5))
        enable.tap()
        waitForPhase("ready")
    }

    func testLandscapeCanFinishAndCancel() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        activateDiagnostic()
        tapButton("voice.record")
        waitForPhase("recording")
        tapButton("voice.cancel")
        waitForPhase("cancelled")
        capture("Landscape cancellation")
    }

    func waitForPhase(_ phase: String) {
        let status = app.staticTexts["voice.status"]
        reveal(status, down: true)
        let predicate = NSPredicate(format: "value == %@", phase)
        expectation(for: predicate, evaluatedWith: status)
        waitForExpectations(timeout: 10)
    }

    func tapButton(_ id: String, down: Bool = false) {
        let button = app.buttons[id]
        reveal(button, down: down)
        button.tap()
    }

    func reveal(_ element: XCUIElement, down: Bool = false) {
        let content = app.collectionViews.matching(NSPredicate(format: "label != %@", "Sidebar")).firstMatch
        for _ in 0..<12 where !element.isHittable {
            if down { content.swipeDown() }
            else { content.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
    }

    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
