import XCTest

/// Hold-to-talk on the keyboard voice key, the press, speak, release habit of Doubao and WeChat.
/// Fixed speech comes from scripts/test-ios-device-audio.py, which honours the marker's delay.
extension UtterSimulatorFlow {
    /// The key is held through the whole 5.4s sample and never tapped to stop: the release alone must end the recording.
    func testDeviceKeyboardHoldToTalk() throws {
        try prepareHoldKeyboard()
        let field = searchField
        let original = field.value as? String ?? ""
        let before = original == field.placeholderValue ? "" : original
        capture("Keyboard ready for hold to talk")
        // Speech starts 3s after the marker, once the press has begun recording, and ends about 8.5s in.
        FileHandle.standardOutput.write(Data("UTTER_AUDIO_READY zh \(Date().timeIntervalSince1970) delay=3.0\n".utf8))
        settings.buttons["keyboard.start"].press(forDuration: 10)
        capture("Keyboard right after the voice key was released")
        XCTAssertTrue(settings.buttons["keyboard.undo"].waitForExistence(timeout: 100),
                      "Releasing the key must end the recording and leave the dictation in the field")
        let value = field.value as? String ?? ""
        let recognized = String(value.dropFirst(before.count))
        print("DEVICE_HOLD_RESULT \(recognized)")
        XCTAssertTrue(value.hasPrefix(before) && recognized.contains("公园") && recognized.contains("水"), recognized)
    }

    /// A hold released before the app confirmed the start must not turn into a recording a moment later.
    func testDeviceKeyboardHoldReleasedEarlyDoesNotRecordLate() throws {
        try prepareHoldKeyboard()
        settings.buttons["keyboard.start"].press(forDuration: 0.6)
        Thread.sleep(forTimeInterval: 6)
        let status = settings.staticTexts["keyboard.status"].value as? String
        print("DEVICE_HOLD_EARLY_RELEASE status=\(status ?? "nil")")
        capture("Keyboard six seconds after a hold released early")
        XCTAssertNotEqual(status, "recording", "A start the user already released must not begin recording later")
        XCTAssertNotEqual(status, "preparing", "An early release must not leave the keyboard waiting")
        XCTAssertFalse(settings.buttons["keyboard.undo"].exists, "An early release must not leave a dictation behind")
        XCTAssertTrue(settings.buttons["keyboard.start"].waitForExistence(timeout: 10), "The key must be usable again")
        settings.buttons["keyboard.start"].tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'recording'"), object: settings.staticTexts["keyboard.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [recording], timeout: 15), .completed, "A normal tap must still start recording")
        settings.buttons["keyboard.cancel"].tap()
        let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'cancelled'"), object: settings.staticTexts["keyboard.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 10), .completed)
    }

    private func prepareHoldKeyboard() throws {
        addTeardownBlock { self.settings.terminate(); self.app.activate(); self.tapIfPresent("voice.disable"); self.app.terminate() }
        launchDeviceRelease()
        try enableStandby()
        try openSettingsSearch()
        selectStandbyKeyboard()
    }
}
