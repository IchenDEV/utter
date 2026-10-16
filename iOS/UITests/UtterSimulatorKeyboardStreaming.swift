import XCTest

/// The keyboard writes the dictation into the host field while it is spoken, then settles and can take it back.
/// The simulator stands in for recognition with a four-step draft of "Utter bridge sample" and a rewrite that adds a full stop.
extension UtterSimulatorFlow {
    private var raw: String { "Utter bridge sample" }

    func testKeyboardStreamsPolishesAndUndoes() {
        let field = prepareStreamingField()
        startKeyboardSession()
        waitForMatch(field, "value BEGINSWITH %@", "Utt")
        XCTAssertEqual(app.staticTexts["keyboard.status"].value as? String, "recording", "Text appears before the recording ends")
        XCTAssertFalse(app.buttons["keyboard.insert"].exists, "There is no separate insert step")
        capture("Dictation streaming into the host field")
        app.buttons["keyboard.stop"].tap()
        waitForMatch(field, "value == %@", raw + ".", timeout: 20)
        XCTAssertTrue(app.buttons["keyboard.undo"].waitForExistence(timeout: 5))
        capture("Dictation rewritten in place")
        app.buttons["keyboard.undo"].tap()
        waitForMatch(field, "value == %@", raw)
        app.buttons["keyboard.undo"].tap()
        waitForMatch(field, "NOT (value BEGINSWITH %@)", "Utter")
        XCTAssertFalse(app.buttons["keyboard.undo"].exists)
        capture("Dictation taken back in two undo steps")
    }

    func testKeyboardWithoutPolishLeavesRecognizedTextAndUndoesInOneStep() {
        let field = prepareStreamingField(arguments: ["-mobile.polish", "NO"])
        startKeyboardSession()
        app.buttons["keyboard.stop"].tap()
        waitForMatch(field, "value == %@", raw)
        XCTAssertTrue(app.buttons["keyboard.undo"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(field.value as? String, raw, "With polishing off the recognized text stays as it is")
        app.buttons["keyboard.undo"].tap()
        waitForMatch(field, "NOT (value BEGINSWITH %@)", "Utter")
    }

    func testKeyboardEditingAfterDictationKeepsTextAndDropsUndo() {
        let field = prepareStreamingField()
        startKeyboardSession()
        app.buttons["keyboard.stop"].tap()
        waitForMatch(field, "value == %@", raw + ".", timeout: 20)
        app.buttons["keyboard.delete"].tap()
        waitForMatch(field, "value == %@", raw)
        app.buttons["keyboard.space"].tap()
        waitForMatch(field, "value == %@", raw + " ")
        XCTAssertFalse(app.buttons["keyboard.undo"].exists, "Editing makes the dictation final")
        app.buttons["keyboard.return"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["keyboard.return"])
        waitForExpectations(timeout: 5)
        capture("Keyboard editing after a dictation")
    }

    func testKeyboardLeavesWrittenTextWhenTheFieldChangesMidDictation() {
        let first = prepareStreamingField()
        let second = app.textFields["field.second"]
        startKeyboardSession()
        waitForMatch(first, "value BEGINSWITH %@", "Utt")
        reveal(second); second.tap()
        waitForMatch(app.staticTexts["keyboard.status"], "value == %@", "cancelled")
        XCTAssertEqual(second.value as? String, "Second field", "Another field is never written to")
        XCTAssertTrue((first.value as? String ?? "").hasPrefix("Utt"), "Text already written stays")
        XCTAssertFalse(app.buttons["keyboard.undo"].exists, "A dictation that was cut off offers no undo")
        capture("Field changed during streaming, writing stopped")
    }

    @MainActor
    func testKeyboardDelayedCancelDoesNotStopNextDictation() async throws {
        let field = prepareStreamingField(arguments: ["--simulator-delayed-cancel"])
        startKeyboardSession()
        app.buttons["keyboard.cancel"].tap()
        waitForMatch(app.staticTexts["keyboard.status"], "value == %@", "cancelled")
        waitForMatch(field, "NOT (value BEGINSWITH %@)", "Utter")
        startKeyboardSession()
        try await Task.sleep(for: .seconds(10))
        XCTAssertEqual(app.staticTexts["keyboard.status"].value as? String, "recording")
        app.buttons["keyboard.stop"].tap()
        waitForMatch(field, "value == %@", raw + ".", timeout: 20)
        capture("Delayed old cancel rejected during next dictation")
    }

    private func prepareStreamingField(arguments: [String] = []) -> XCUIElement {
        activateSimulatorHost(arguments: arguments)
        let field = app.textFields["field.first"]
        reveal(field); field.tap()
        selectUtterKeyboard()
        return field
    }

    private func waitForMatch(_ element: XCUIElement, _ format: String, _ argument: String, timeout: TimeInterval = 10) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, argument), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed,
                       "\(element.identifier) did not match \(format) \(argument); value=\(String(describing: element.value))")
    }
}
