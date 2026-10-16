import XCTest

@MainActor
final class UtterSimulatorFlow: XCTestCase {
    var safariTabID: String?
    let app = XCUIApplication(bundleIdentifier: "com.ichendev.utter.ios")
    var host: XCUIApplication { XCUIApplication(bundleIdentifier: name.contains("Safari") ? "com.apple.mobilesafari" :
        (name.contains("Settings") ? "com.apple.Preferences" : "com.ichendev.utter.standbyhost")) }
    private var inputField: XCUIElement { name.contains("Safari") ? host.textViews["Fixed test text"] :
        (name.contains("Settings") ? host.searchFields.firstMatch : host.textFields["host.field"]) }

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        if !name.contains("Safari"), host.state != .notRunning { host.terminate() }
        if name.contains("testReal") {
            app.launchArguments = ["--standby-real-audio", "-mobile.model", "apple", "-mobile.language", "zh"]
        }
        if name.contains("NoAudio") { app.launchArguments += ["--standby-no-audio"] }
        if name.contains("AudioActivationControl") { app.launchArguments += ["--standby-audio-control"] }
        if name.contains("SampleBuffer") { app.launchArguments += ["--standby-sample-buffer"] }
        app.terminate(); app.launch()
    }
    override func tearDown() async throws {
        if name.contains("Safari") {
            try await cleanupSafariFixture()
        } else if host.state != .notRunning { host.terminate() }
        app.activate()
        if app.buttons["probe.stop"].exists {
            app.buttons["probe.stop"].tap()
            XCTAssertTrue(app.staticTexts["disabled"].waitForExistence(timeout: 10), "Stop must finish before termination")
        }
        app.terminate()
    }

    func testPiPStartAndStop() throws {
        XCTAssertTrue(app.buttons["probe.pip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["probe.pip"].isHittable)
        app.buttons["probe.pip"].tap()
        if app.staticTexts["unsupported"].waitForExistence(timeout: 2) {
            capture("Video-call PiP unsupported on this device")
            throw XCTSkip("AVPictureInPictureController reports unsupported")
        }
        XCTAssertTrue(app.staticTexts["active"].waitForExistence(timeout: 10))
        capture("Video-call PiP started; inspect actual window size")
        app.buttons["probe.stop"].tap()
        XCTAssertTrue(app.staticTexts["disabled"].waitForExistence(timeout: 5))
        capture("Video-call PiP stopped")
    }

    func testRealKeyboardBackgroundSpeech() async throws {
        try await prepareRealStandby()
        selectKeyboard()
        try await Task.sleep(for: .seconds(10))
        try await dictateReal()
    }

    func testRealSettingsKeyboardBackgroundSpeech() async throws {
        XCTAssertTrue(app.buttons["probe.pip"].waitForExistence(timeout: 5))
        app.buttons["probe.pip"].tap()
        XCTAssertTrue(app.staticTexts["active"].waitForExistence(timeout: 30))
        host.launch()
        for _ in 0..<4 where !inputField.exists {
            let back = host.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Settings", "设置", "Apps", "App", "应用"])).firstMatch
            if back.exists { back.tap() } else { break }
        }
        guard inputField.waitForExistence(timeout: 5) else {
            print("SETTINGS_HOST_UI \(host.debugDescription)")
            XCTFail("Settings search field must be visible"); return
        }
        selectKeyboard()
        try await Task.sleep(for: .seconds(10))
        try await dictateReal()
    }

    func testRealExternalVideoAfterStandby() async throws {
        try await prepareRealStandby()
        host.buttons["host.video"].tap()
        await fulfillment(of: [expectation(for: NSPredicate(format: "label == 'active'"),
                                          evaluatedWith: host.staticTexts["host.video_status"])], timeout: 10)
        selectKeyboard()
        let position = Double(host.staticTexts["host.video_position"].label) ?? 0
        try await dictateReal()
        XCTAssertEqual(host.staticTexts["host.video_status"].label, "active")
        XCTAssertGreaterThan(Double(host.staticTexts["host.video_position"].label) ?? 0, position + 5)
        XCTAssertGreaterThan(Double(host.staticTexts["host.video_rate"].label) ?? 0, 0)
        capture("Real speech with external video; inspect visual coexistence")
    }

    private func prepareRealStandby() async throws {
        XCTAssertTrue(app.buttons["probe.pip"].waitForExistence(timeout: 5))
        app.buttons["probe.pip"].tap()
        XCTAssertTrue(app.staticTexts["active"].waitForExistence(timeout: 30))
        host.launch()
        XCTAssertTrue(host.staticTexts["host.probe_status"].waitForExistence(timeout: 5))
    }

    func dictateReal() async throws {
        XCTAssertEqual(host.state, .runningForeground)
        let field = inputField
        let original = field.value as? String ?? ""
        let before = original == field.placeholderValue ? "" : original
        host.buttons["keyboard.start"].tap()
        let recording = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'recording'"),
                                                  object: host.staticTexts["keyboard.status"])
        let outcome = await XCTWaiter.fulfillment(of: [recording], timeout: 15)
        print("REAL_STANDBY start=\(outcome.rawValue) keyboard=\(host.staticTexts["keyboard.status"].value ?? "unknown")")
        capture("Real background recording gate")
        guard outcome == .completed else {
            XCTFail("Actual recording must start before fixed speech playback")
            throw NSError(domain: "StandbyCapture", code: 1)
        }
        XCTAssertEqual(host.state, .runningForeground)
        FileHandle.standardOutput.write(Data("UTTER_AUDIO_READY zh \(Date().timeIntervalSince1970)\n".utf8))
        try await Task.sleep(for: .seconds(12))
        host.buttons["keyboard.stop"].tap()
        XCTAssertTrue(host.buttons["keyboard.insert"].waitForExistence(timeout: 100))
        XCTAssertEqual(host.state, .runningForeground)
        let recognized = host.staticTexts["keyboard.result"].label
        XCTAssertTrue(recognized.contains("公园") && recognized.contains("水"))
        host.buttons["keyboard.insert"].tap()
        capture("Immediately after real keyboard insertion")
        print("REAL_STANDBY insertedLength=\((field.value as? String ?? "").count)")
        await fulfillment(of: [expectation(for: NSPredicate(format: "value == %@", before + recognized), evaluatedWith: field)], timeout: 5)
        XCTAssertFalse(host.buttons["keyboard.insert"].exists)
        capture("Real background speech inserted into external host")
    }

    func testPlainBackgroundControl() async throws {
        app.buttons["probe.plain"].tap()
        XCTAssertTrue(app.staticTexts["ready"].waitForExistence(timeout: 5))
        host.launch()
        XCTAssertTrue(host.staticTexts["host.probe_status"].waitForExistence(timeout: 5))
        try await Task.sleep(for: .seconds(75))
        selectKeyboard()
        // A pass here means the simulator did not suspend the control; PiP causality is inconclusive.
        try await dictate()
        capture("Plain background Start Stop Insert after 75 seconds")
    }

    func testDevicePlainBackgroundTicks() async throws {
        try await measureBackground(withPiP: false)
    }

    func testDevicePiPBackgroundTicks() async throws {
        try await measureBackground(withPiP: true)
    }

    private func measureBackground(withPiP: Bool) async throws {
        let button = app.buttons[withPiP ? "probe.pip" : "probe.plain"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(app.staticTexts[withPiP ? "active" : "ready"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        print("SYSTEM APP STATE after Home: \(app.state.rawValue)")
        capture(withPiP ? "PiP background screen" : "Plain background screen")
        try await Task.sleep(for: .seconds(75))
        capture(withPiP ? "PiP screen after 75 seconds" : "Plain screen after 75 seconds")
        app.activate()
        let ticks = Int(app.staticTexts["probe.background_ticks"].label) ?? -1
        let gap = Double(app.staticTexts["probe.background_gap"].label) ?? -1
        let seconds = Double(app.staticTexts["probe.background_seconds"].label) ?? -1
        let actualPiP = app.staticTexts["probe.resumed_pip"].label
        print("BACKGROUND withPiP=\(withPiP) ticks=\(ticks) maxGap=\(gap) seconds=\(seconds) resumedPiP=\(actualPiP)")
        capture("Background execution counters PiP=\(withPiP)")
        XCTAssertGreaterThan(seconds, 70)
        if withPiP {
            XCTAssertEqual(actualPiP, "active")
            XCTAssertGreaterThan(ticks, 200)
            XCTAssertGreaterThanOrEqual(gap, 0)
            XCTAssertLessThan(gap, 3)
        } else {
            XCTAssertGreaterThanOrEqual(ticks, 0)
        }
        app.buttons["probe.stop"].tap()
        XCTAssertTrue(app.staticTexts["disabled"].waitForExistence(timeout: 6))
    }

    func testPiPBackgroundAndExternalVideo() async throws {
        app.buttons["probe.pip"].tap()
        if app.staticTexts["unsupported"].waitForExistence(timeout: 2) {
            capture("Video-call PiP unsupported by simulator")
            throw XCTSkip("AVPictureInPictureController reports unsupported on this simulator")
        }
        XCTAssertTrue(app.staticTexts["active"].waitForExistence(timeout: 10))
        host.launch()
        try await Task.sleep(for: .seconds(75))
        XCTAssertEqual(host.staticTexts["host.probe_status"].label, "active")
        selectKeyboard()
        try await dictate()
        capture("Video-call PiP background insertion after 75 seconds")
        try await Task.sleep(for: .seconds(305))
        try await dictate()
        capture("Background insertion after five minutes idle")
        host.buttons["host.video"].tap()
        XCTAssertTrue(host.staticTexts["host.video_status"].waitForExistence(timeout: 5))
        let active = expectation(for: NSPredicate(format: "label == %@", "active"),
                                 evaluatedWith: host.staticTexts["host.video_status"])
        await fulfillment(of: [active], timeout: 10)
        try await Task.sleep(for: .seconds(3))
        XCTAssertEqual(host.staticTexts["host.probe_status"].label, "active", "Starting another video PiP displaced standby PiP")
        let position = Double(host.staticTexts["host.video_position"].label) ?? 0
        capture("External video PiP coexistence")
        try await Task.sleep(for: .seconds(45))
        XCTAssertEqual(host.staticTexts["host.video_status"].label, "active")
        XCTAssertEqual(host.staticTexts["host.probe_status"].label, "active")
        XCTAssertGreaterThan(Double(host.staticTexts["host.video_position"].label) ?? 0, position + 30)
        XCTAssertGreaterThan(Double(host.staticTexts["host.video_rate"].label) ?? 0, 0)
        try await dictate()
        capture("Keyboard input while external video PiP plays")
    }

    func testExternalVideoPiPControl() async throws {
        host.launch()
        host.buttons["host.video"].tap()
        XCTAssertTrue(host.staticTexts["host.video_status"].waitForExistence(timeout: 5))
        if host.staticTexts["host.video_status"].label == "unsupported" {
            capture("Ordinary video PiP unsupported by simulator")
            throw XCTSkip("Ordinary video PiP also reports unsupported on this simulator")
        }
        await fulfillment(of: [expectation(for: NSPredicate(format: "label == %@", "active"),
                                           evaluatedWith: host.staticTexts["host.video_status"])], timeout: 10)
        capture("Ordinary external video PiP control")
    }

    func selectKeyboard() {
        inputField.tap()
        if !host.staticTexts["keyboard.status"].exists {
            let globe = host.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一个键盘"])).firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5))
            globe.press(forDuration: 1)
            let utter = host.tables["InputSwitcherTable"].cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Utter")).firstMatch
            XCTAssertTrue(utter.waitForExistence(timeout: 5)); utter.tap()
        }
        XCTAssertTrue(host.buttons["keyboard.start"].waitForExistence(timeout: 5))
    }

    private func dictate() async throws {
        let field = host.textFields["host.field"]
        let value = field.value as? String ?? ""
        let before = value == "Fixed test text" ? "" : value
        host.buttons["keyboard.start"].tap()
        await fulfillment(of: [expectation(for: NSPredicate(format: "value == %@", "recording"),
                                           evaluatedWith: host.staticTexts["keyboard.status"])], timeout: 15)
        host.buttons["keyboard.stop"].tap()
        XCTAssertTrue(host.buttons["keyboard.insert"].waitForExistence(timeout: 10))
        host.buttons["keyboard.insert"].tap()
        await fulfillment(of: [expectation(for: NSPredicate(format: "value == %@", before + "Utter bridge sample"),
                                           evaluatedWith: field)], timeout: 5)
        XCTAssertFalse(host.buttons["keyboard.insert"].exists)
    }

    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
