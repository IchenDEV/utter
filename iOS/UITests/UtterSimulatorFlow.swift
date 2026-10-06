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

    func testKeyboardEndToEnd() {
        activateDiagnostic()
        app.textFields["field.first"].tap()
        selectUtterKeyboard()
        capture("Keyboard selection")
        startKeyboardSession()
        app.buttons["keyboard.stop"].tap()
        XCTAssertTrue(app.buttons["keyboard.insert"].waitForExistence(timeout: 10))
        app.buttons["keyboard.insert"].tap()
        XCTAssertEqual(app.textFields["field.first"].value as? String, "Utter bridge sample")
        XCTAssertFalse(app.buttons["keyboard.insert"].exists)
        capture("Single keyboard result insertion")
    }

    func testSimulatorKeyboardTransportAndEditing() {
        activateSimulatorHost()
        let field = app.textFields["field.first"]
        reveal(field); field.tap()
        selectUtterKeyboard()
        startKeyboardSession()
        capture("Simulator keyboard recording controls")
        app.buttons["keyboard.stop"].tap()
        XCTAssertTrue(app.buttons["keyboard.insert"].waitForExistence(timeout: 10))
        app.buttons["keyboard.insert"].tap()
        waitForValue(field, "Utter bridge sample")
        XCTAssertFalse(app.buttons["keyboard.insert"].exists)
        app.buttons["keyboard.delete"].tap()
        waitForValue(field, "Utter bridge sampl")
        app.buttons["keyboard.space"].tap()
        waitForValue(field, "Utter bridge sampl ")
        app.buttons["keyboard.return"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["keyboard.return"])
        waitForExpectations(timeout: 5)
        waitForPhase("ready")
        XCTAssertFalse(app.buttons["voice.copy"].exists)
        capture("Simulator foreground transport and keyboard editing")
    }

    func testSimulatorFieldChangeCancelsAndRejectsOldResult() {
        activateSimulatorHost()
        let first = app.textFields["field.first"]
        let second = app.textFields["field.second"]
        reveal(first); first.tap()
        selectUtterKeyboard()
        startKeyboardSession()
        reveal(second); second.tap()
        expectation(for: NSPredicate(format: "value == %@", "cancelled"), evaluatedWith: app.staticTexts["keyboard.status"])
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["keyboard.insert"].exists)
        startKeyboardSession()
        app.buttons["keyboard.stop"].tap()
        XCTAssertTrue(app.buttons["keyboard.insert"].waitForExistence(timeout: 10))
        reveal(first); first.tap()
        XCTAssertFalse(app.buttons["keyboard.insert"].exists)
        XCTAssertEqual(second.value as? String, "Second field")
        startKeyboardSession()
        app.buttons["keyboard.stop"].tap()
        XCTAssertTrue(app.buttons["keyboard.insert"].waitForExistence(timeout: 10))
        app.buttons["keyboard.insert"].tap()
        waitForValue(first, "Utter bridge sample")
        XCTAssertEqual(second.value as? String, "Second field")
        capture("Old field results rejected and new session inserted")
    }

    @MainActor
    func testSimulatorDelayedCancelDoesNotStopNextSession() async throws {
        activateSimulatorHost(arguments: ["--simulator-delayed-cancel"])
        let field = app.textFields["field.first"]
        reveal(field); field.tap()
        selectUtterKeyboard()
        startKeyboardSession()
        app.buttons["keyboard.cancel"].tap()
        await fulfillment(of: [expectation(for: NSPredicate(format: "value == %@", "cancelled"),
                                         evaluatedWith: app.staticTexts["keyboard.status"])], timeout: 10)
        startKeyboardSession()
        try await Task.sleep(for: .seconds(10))
        XCTAssertEqual(app.staticTexts["keyboard.status"].value as? String, "recording")
        app.buttons["keyboard.stop"].tap()
        XCTAssertTrue(app.buttons["keyboard.insert"].waitForExistence(timeout: 10))
        app.buttons["keyboard.insert"].tap()
        waitForValue(field, "Utter bridge sample")
        capture("Delayed old cancel rejected during next recording")
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
        let paste = app.menuItems["Paste"].exists ? app.menuItems["Paste"] : app.buttons["Paste"].firstMatch
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

    private func startKeyboardSession() {
        XCTAssertTrue(app.buttons["keyboard.start"].waitForExistence(timeout: 5))
        app.buttons["keyboard.start"].tap()
        expectation(for: NSPredicate(format: "value == %@", "recording"), evaluatedWith: app.staticTexts["keyboard.status"])
        waitForExpectations(timeout: 15)
    }

    private func activateSimulatorHost(arguments: [String] = []) {
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
