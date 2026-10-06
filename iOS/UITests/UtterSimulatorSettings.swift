import XCTest

extension UtterSimulatorFlow {
    func openProductPage(_ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.exists { tab.tap(); return }
        let sidebar = app.descendants(matching: .any).matching(identifier: "tab.\(name.lowercased())").firstMatch
        if !sidebar.isHittable {
            let toggle = app.buttons.matching(NSPredicate(format: "label IN %@", ["Toggle Sidebar", "Show Sidebar"])).firstMatch
            if toggle.exists { toggle.tap() }
        }
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5)); sidebar.tap()
    }

    func testProductNavigationAndPreferences() {
        capture("Product voice page")
        openProductPage("Models")
        XCTAssertTrue(app.descendants(matching: .any)["model.apple.download"].waitForExistence(timeout: 10))
        let downloads = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model.download."))
        XCTAssertGreaterThan(downloads.count, 0)
        capture("Product models with real download actions")
        openProductPage("Settings")
        let haptics = app.switches["settings.haptics"]
        reveal(haptics)
        let original = haptics.value as? String
        haptics.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changedExpected = original == "1" ? "0" : "1"
        waitForValue(haptics, changedExpected)
        let changed = haptics.value as? String
        XCTAssertNotEqual(original, changed)
        app.terminate(); app.launch()
        openProductPage("Settings"); reveal(haptics)
        XCTAssertEqual(haptics.value as? String, changed)
        haptics.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForValue(haptics, original ?? "1")
        XCTAssertEqual(haptics.value as? String, original)
        capture("Product settings with persistent keyboard feedback")
        tapButton("dictionary.open", down: true)
        let originalField = app.textFields["dictionary.original"]
        XCTAssertTrue(originalField.waitForExistence(timeout: 5))
        let testPhrase = "Utter test " + UUID().uuidString.prefix(8)
        originalField.tap(); originalField.typeText(testPhrase)
        app.textFields["dictionary.replacement"].tap(); app.textFields["dictionary.replacement"].typeText("Mobile replacement")
        XCTAssertTrue(app.buttons["dictionary.add"].isEnabled)
        app.buttons["dictionary.add"].tap()
        let entry = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "dictionary.entry.", testPhrase)).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        let deleteID = entry.identifier.replacingOccurrences(of: "dictionary.entry.", with: "dictionary.delete.")
        entry.swipeLeft()
        app.buttons[deleteID].tap()
        XCTAssertFalse(entry.exists)
        capture("Dictionary works without microphone permission")
    }

    func testNativeProductRotation() {
        openProductPage("Models")
        XCUIDevice.shared.orientation = .landscapeLeft
        reveal(app.descendants(matching: .any)["model.apple.download"])
        XCTAssertTrue(app.descendants(matching: .any)["model.apple.download"].waitForExistence(timeout: 5))
        capture("Native landscape model library")
        openProductPage("Settings")
        capture("Native landscape settings")
        XCUIDevice.shared.orientation = .portrait
        openProductPage("Voice")
        capture("Native portrait voice page")
    }

    func testProductGlobe() {
        let field = app.textFields["field.first"]
        reveal(field); field.tap()
        selectUtterKeyboard()
        let globe = app.buttons["keyboard.globe"]
        XCTAssertTrue(globe.waitForExistence(timeout: 5))
        XCTAssertTrue(globe.isHittable)
        capture("Product keyboard with bottom right globe")
        globe.tap()
        let next = app.buttons["Next keyboard"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["keyboard.space"].exists)
        capture("Product globe switched to the system keyboard")
        selectUtterKeyboard()
        XCTAssertTrue(app.buttons["keyboard.space"].waitForExistence(timeout: 5))
        capture("Returned to Utter through the native keyboard selector")
    }

    func testModelDownloadCancelRetry() throws {
        openProductPage("Models")
        let download = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model.download.openai_whisper-tiny")).firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        let id = String(download.identifier.dropFirst("model.download.".count))
        download.tap()
        let cancel = app.buttons["model.cancel.\(id)"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        capture("Real model transfer started")
        cancel.tap()
        XCTAssertTrue(download.waitForExistence(timeout: 30))
        capture("Cancelled download offers retry")
        download.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        cancel.tap()
        XCTAssertTrue(download.waitForExistence(timeout: 30))
    }

    func testModelDownloadSelectRestartDelete() throws {
        openProductPage("Models")
        let existing = app.buttons["model.delete.openai_whisper-tiny"]
        if existing.waitForExistence(timeout: 2) { throw XCTSkip("Preserve the pre-existing model; lifecycle requires an absent test model") }
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model.use.")).allElementsBoundByIndex.first { !$0.isEnabled }?.identifier
        let download = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model.download.openai_whisper-tiny")).firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        let id = String(download.identifier.dropFirst("model.download.".count))
        download.tap()
        let use = app.buttons["model.use.\(id)"]
        XCTAssertTrue(use.waitForExistence(timeout: 300), "Real model download and integrity validation must finish")
        use.tap()
        XCTAssertFalse(use.isEnabled)
        capture("Downloaded model selected")
        app.terminate(); app.launch()
        openProductPage("Models")
        XCTAssertTrue(use.waitForExistence(timeout: 10))
        XCTAssertFalse(use.isEnabled, "Selection must survive restart")
        app.buttons["model.delete.\(id)"].tap()
        app.buttons["model.delete.confirm"].firstMatch.tap()
        XCTAssertTrue(download.waitForExistence(timeout: 20))
        XCTAssertFalse(use.exists)
        if let selected, app.buttons[selected].exists { app.buttons[selected].tap() }
        capture("Deleted model offers download again")
    }

    func testNativeAccessibilityAudit() throws {
        activateDiagnostic()
        continueAfterFailure = true
        try app.performAccessibilityAudit { issue in
            print("Accessibility issue: \(issue.auditType) \(issue.element?.debugDescription ?? "unknown element")")
            self.capture("Live main audit issue \(issue.auditType.rawValue)")
            return false
        }
        let field = app.textFields["field.first"]
        reveal(field); field.tap()
        selectUtterKeyboard()
        capture("Keyboard before accessibility audit")
        try app.performAccessibilityAudit { issue in
            print("Accessibility issue: \(issue.auditType) \(issue.element?.debugDescription ?? "unknown element")")
            self.capture("Live keyboard audit issue \(issue.auditType.rawValue)")
            return false
        }
    }

    func testRecordingLimitFinishesWithResult() {
        openProductPage("Settings")
        let duration = app.buttons["settings.duration"]
        reveal(duration); duration.tap()
        app.buttons["30 seconds"].firstMatch.tap()
        openProductPage("Voice")
        activateDiagnostic()
        tapButton("voice.record", down: true)
        waitForPhase("recording")
        expectation(for: NSPredicate(format: "value == %@", "result"), evaluatedWith: app.staticTexts["voice.status"])
        waitForExpectations(timeout: 40)
        reveal(app.staticTexts["Utter bridge sample"])
        XCTAssertTrue(app.staticTexts["Utter bridge sample"].exists)
        capture("Recording limit returns the captured text")
        tapButton("voice.record", down: true)
        waitForPhase("recording")
        tapButton("voice.cancel")
        waitForPhase("cancelled")
        XCTAssertFalse(app.staticTexts["Utter bridge sample"].exists)
        openProductPage("Settings")
        reveal(duration); duration.tap()
        app.buttons["120 seconds"].firstMatch.tap()
    }

    func testLargeTextNavigationEvidence() {
        activateDiagnostic()
        reveal(app.staticTexts["voice.status"], down: true)
        capture("Dynamic Type main controls")
        for title in ["Try the keyboard", "Voice keyboard"] {
            let heading = app.staticTexts[title].firstMatch
            reveal(heading)
            XCTAssertTrue(heading.isHittable)
            print("Dynamic Type heading \(title): \(heading.frame)")
            capture("Dynamic Type \(title)")
        }
        let dictionary = app.buttons["dictionary.open"]
        reveal(dictionary)
        XCTAssertTrue(dictionary.isHittable)
        print("Dynamic Type dictionary: \(dictionary.frame)")
        capture("Dynamic Type dictionary navigation")
        dictionary.tap()
        XCTAssertTrue(app.textFields["dictionary.original"].waitForExistence(timeout: 5))
        reveal(app.buttons["dictionary.add"])
        XCTAssertFalse(app.buttons["dictionary.add"].isEnabled)
        capture("Dynamic Type dictionary form")
    }

    func testKeyboardEditsWithoutFullAccess() throws {
        let field = app.textFields["field.first"]
        reveal(field); field.tap()
        selectUtterKeyboard()
        let label = app.staticTexts["keyboard.status"].label
        guard label.contains("完全访问") || label.contains("Full Access") else {
            throw XCTSkip("Requires Full Access off in the designated test simulator.")
        }
        XCTAssertFalse(app.buttons["keyboard.start"].exists)
        app.buttons["keyboard.space"].tap()
        app.buttons["keyboard.space"].tap()
        waitForValue(field, "  ")
        app.buttons["keyboard.delete"].tap()
        waitForValue(field, " ")
        app.buttons["keyboard.return"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["keyboard.return"])
        waitForExpectations(timeout: 5)
        capture("Full Access off, native space delete and Return work")
    }

    func testLanguageChangeDisablesCurrentRuntime() {
        activateDiagnostic()
        openProductPage("Settings")
        let picker = app.buttons["voice.language"]
        reveal(picker, down: true); picker.tap()
        let english = app.buttons["English"].firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 3))
        english.tap()
        openProductPage("Voice")
        waitForPhase("disabled")
        XCTAssertFalse(app.buttons["voice.record"].exists)
        activateDiagnostic()
        waitForPhase("ready")
        capture("Language change resets runtime before re-enabling")
    }

    func testChineseInterfaceSession() {
        app.terminate()
        app.launchArguments = ["--bridge-diagnostic", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        activateDiagnostic()
        tapButton("voice.record", down: true)
        waitForPhase("recording")
        XCTAssertEqual(app.staticTexts["voice.status"].label, "正在录音")
        tapButton("voice.cancel")
        waitForPhase("cancelled")
        capture("Chinese native interface and cancellation")
    }

    func testLiveActivityPresentationEvidence() {
        activateDiagnostic()
        tapButton("voice.record", down: true)
        waitForPhase("recording")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 5))
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: springboard.icons["Utter"].firstMatch)
        waitForExpectations(timeout: 5)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Live Activity presentation, synthetic session, inspect visually"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.activate()
        tapButton("voice.cancel")
        waitForPhase("cancelled")
    }

    func testLiveActivityStopAndCancel() {
        activateDiagnostic()
        for cancel in [false, true] {
            tapButton("voice.record", down: true)
            waitForPhase("recording")
            XCUIDevice.shared.press(.home)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: springboard.icons["Utter"].firstMatch)
            waitForExpectations(timeout: 5)
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).press(forDuration: 1)
            let action = springboard.buttons[cancel ? "activity.cancel" : "activity.stop"]
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            let expanded = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            expanded.name = "Expanded Live Activity \(cancel ? "Cancel" : "Stop")"
            expanded.lifetime = .keepAlways; add(expanded)
            action.tap()
            app.activate()
            waitForPhase(cancel ? "cancelled" : "result")
            XCUIDevice.shared.press(.home)
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: springboard.icons["Utter"].firstMatch)
            waitForExpectations(timeout: 5)
            let ended = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            ended.name = "Live Activity removed after \(cancel ? "Cancel" : "Stop")"
            ended.lifetime = .keepAlways; add(ended)
            app.activate()
        }
    }
}
