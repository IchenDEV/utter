import XCTest

extension UtterSimulatorFlow {
    func testDeviceAppleChineseSpeech() throws {
        launchDeviceRelease()
        try preserveSpeechConfiguration()
        try prepareDeviceSpeech(language: "Mandarin", apple: true)
        try captureDeviceSpeech(sample: "zh", expected: ["今天下午", "公园", "一瓶水"])
        let recognized = app.staticTexts["voice.result"].label
        XCTAssertNotNil(recognized.range(of: "三点|3[:：]00|3点", options: .regularExpression))
        tapButton("voice.copy")
        let field = app.textFields["field.first"]
        reveal(field); field.tap(); field.press(forDuration: 1)
        let paste = app.menuItems["Paste"].exists ? app.menuItems["Paste"] : app.buttons["Paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5)); paste.tap()
        waitForValue(field, recognized)
        if app.buttons["keyboard.return"].exists { app.buttons["keyboard.return"].tap() }
        tapButton("voice.discard")
        waitForPhase("ready")
        XCTAssertFalse(app.staticTexts["voice.result"].exists)
        tapButton("voice.disable")
        waitForPhase("disabled")
    }

    func testDeviceAppleEnglishBackgroundSpeech() throws {
        launchDeviceRelease()
        try preserveSpeechConfiguration()
        try prepareDeviceSpeech(language: "English", apple: true)
        try captureDeviceSpeech(sample: "en", expected: ["tomorrow", "library", "notebook"], background: true)
        tapButton("voice.disable")
    }

    func testDeviceRecordingCancellationAndLimit() throws {
        launchDeviceRelease()
        try preserveSpeechConfiguration()
        try prepareDeviceSpeech(language: "Mandarin", apple: true)
        tapButton("voice.record"); waitForPhase("recording")
        FileHandle.standardOutput.write(Data("UTTER_AUDIO_READY cancel \(Date().timeIntervalSince1970)\n".utf8))
        Thread.sleep(forTimeInterval: 2)
        tapButton("voice.cancel"); waitForPhase("cancelled")
        XCTAssertFalse(app.staticTexts["voice.result"].exists)
        capture("Physical microphone cancelled without result")
        openProductPage("Settings")
        let duration = app.buttons["settings.duration"]
        let original = try XCTUnwrap(["30 seconds", "60 seconds", "120 seconds"].first { duration.label.contains($0) || (duration.value as? String) == $0 })
        duration.tap(); app.buttons["30 seconds"].firstMatch.tap()
        openProductPage("Voice")
        try captureDeviceSpeech(sample: "zh", expected: ["公园"], automaticStop: true)
        tapButton("voice.disable")
        openProductPage("Settings")
        duration.tap(); app.buttons[original].firstMatch.tap()
    }

    func testDeviceDownloadedModelSpeech() throws {
        try exerciseDeviceModel("openai_whisper-tiny", downloadTimeout: 300)
    }

    func testDeviceConfuciusSpeech() throws {
        try exerciseDeviceModel("mlx-community/Confucius4-R2T2-8bit", downloadTimeout: 1800)
    }

    private func exerciseDeviceModel(_ id: String, downloadTimeout: TimeInterval) throws {
        launchDeviceRelease()
        try allowDeviceWiFiForTest()
        try preserveSpeechConfiguration()
        openProductPage("Models")
        waitForDeviceModelLibrary()
        let delete = app.buttons["model.delete.\(id)"]
        let preexisting = delete.exists
        let use = app.buttons["model.use.\(id)"]
        if !preexisting {
            let download = app.buttons["model.download.\(id)"]
            XCTAssertTrue(download.exists)
            reveal(download)
            let started = Date()
            download.tap()
            addTeardownBlock {
                self.app.terminate(); self.app.launch(); self.openProductPage("Models")
                self.waitForDeviceModelLibrary()
                let cancel = self.app.buttons["model.cancel.\(id)"]
                if cancel.exists { cancel.tap() }
                if delete.exists {
                    self.reveal(delete)
                    delete.tap(); self.app.buttons["model.delete.confirm"].firstMatch.tap()
                    XCTAssertTrue(self.app.buttons["model.download.\(id)"].waitForExistence(timeout: 20))
                }
            }
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                use.exists || (download.exists && download.label == "Retry")
            }, object: nil)
            let outcome = XCTWaiter.wait(for: [finished], timeout: downloadTimeout)
            print("DEVICE_MODEL_DOWNLOAD id=\(id) seconds=\(Date().timeIntervalSince(started)) ready=\(use.exists)")
            let failure = app.staticTexts["model.error.\(id)"]
            if failure.exists { print("DEVICE_MODEL_DOWNLOAD failure=\(failure.label)") }
            capture("Physical model download outcome")
            XCTAssertEqual(outcome, .completed)
            XCTAssertTrue(use.exists, "Real model transfer and integrity check must succeed")
        }
        reveal(use)
        if use.isEnabled { use.tap() }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: use)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        app.terminate(); app.launch(); openProductPage("Models")
        XCTAssertTrue(use.waitForExistence(timeout: 10)); XCTAssertFalse(use.isEnabled)
        capture("Physical downloaded model selection survives restart")
        try prepareDeviceSpeech(language: "Mandarin", apple: false)
        try captureDeviceSpeech(sample: "zh", expected: ["公园", "水"])
        tapButton("voice.disable")
        openProductPage("Models")
        app.buttons["model.use.apple"].tap()
        if !preexisting {
            reveal(delete)
            delete.tap()
            app.buttons["model.delete.confirm"].firstMatch.tap()
            XCTAssertTrue(app.buttons["model.download.\(id)"].waitForExistence(timeout: 20))
        }
        capture("Physical model lifecycle cleanup")
    }

    func testDeviceModelDownloadCancelRetry() throws {
        launchDeviceRelease()
        try allowDeviceWiFiForTest()
        try testModelDownloadCancelRetry()
    }

    private func allowDeviceWiFiForTest() throws {
        openProductPage("Voice"); tapButton("voice.settings")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5))
        let wireless = settings.staticTexts["无线数据"]
        guard wireless.waitForExistence(timeout: 3) else { app.activate(); return }
        let wasOff = settings.cells.containing(.staticText, identifier: "无线数据").firstMatch.staticTexts["关闭"].exists
        wireless.tap()
        capture("Utter original wireless data selection")
        guard wasOff else { app.activate(); return }
        addTeardownBlock {
            self.app.launch(); self.openProductPage("Voice"); self.tapButton("voice.settings")
            XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5))
            if wireless.exists { wireless.tap() }
            let restore = settings.cells.matching(NSPredicate(format: "label == %@", "关闭")).firstMatch
            XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.tap()
            self.capture("Utter wireless data restored to off")
            self.app.activate(); self.app.terminate()
        }
        let wifi = settings.cells.matching(NSPredicate(format: "label == %@", "无线局域网")).firstMatch
        XCTAssertTrue(wifi.waitForExistence(timeout: 5)); wifi.tap()
        capture("Utter Wi-Fi permitted for model download")
        app.activate()
    }

    private func preserveSpeechConfiguration() throws {
        openProductPage("Models")
        waitForDeviceModelLibrary()
        var model = "model.use.apple"
        if app.buttons[model].exists {
            let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND enabled == false", "model.use.")).firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 10))
            model = selected.identifier
        }
        openProductPage("Settings")
        let language = app.buttons["voice.language"]
        let originalLanguage = try XCTUnwrap(["Mandarin", "English"].first { language.label.contains($0) || (language.value as? String) == $0 })
        let duration = app.buttons["settings.duration"]
        let originalDuration = try XCTUnwrap(["30 seconds", "60 seconds", "120 seconds"].first { duration.label.contains($0) || (duration.value as? String) == $0 })
        addTeardownBlock {
            self.app.terminate()
            self.app.launch(); self.openProductPage("Models")
            self.waitForDeviceModelLibrary()
            let originalModel = self.app.buttons[model]
            if model != "model.use.apple" { XCTAssertTrue(originalModel.waitForExistence(timeout: 10)) }
            if originalModel.exists && originalModel.isEnabled {
                originalModel.tap()
                let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    model == "model.use.apple" ? !originalModel.exists : !originalModel.isEnabled
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
            }
            self.openProductPage("Settings")
            language.tap(); self.app.buttons[originalLanguage].firstMatch.tap()
            duration.tap(); self.app.buttons[originalDuration].firstMatch.tap()
            self.app.terminate()
        }
    }

    private func waitForDeviceModelLibrary() {
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            ["download", "use", "cancel"].contains { self.app.buttons["model.\($0).openai_whisper-tiny"].exists }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed, "Do not infer model absence while the library loads")
    }

    private func prepareDeviceSpeech(language: String, apple: Bool) throws {
        openProductPage("Models")
        if apple, app.buttons["model.use.apple"].exists { app.buttons["model.use.apple"].tap() }
        openProductPage("Settings")
        app.buttons["voice.language"].tap(); app.buttons[language].firstMatch.tap()
        openProductPage("Voice")
        tapButton("voice.enable", down: true)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = system.alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            capture("Physical microphone authorization prompt")
            let message = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ").lowercased()
            XCTAssertTrue(message.contains("microphone") || message.contains("麦克风"), "Only the microphone prompt is authorized here")
            let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "允许", "OK", "好"])).firstMatch
            XCTAssertTrue(allow.exists); allow.tap()
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "ready"), object: app.staticTexts["voice.status"])
        let outcome = XCTWaiter.wait(for: [ready], timeout: 120)
        capture("Physical speech preparation \(language)")
        XCTAssertEqual(outcome, .completed, "Speech preparation must actually reach ready")
    }

    private func captureDeviceSpeech(sample: String, expected: [String], background: Bool = false, automaticStop: Bool = false) throws {
        tapButton("voice.record", down: true)
        waitForPhase("recording")
        if background {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.springboard").wait(for: .runningForeground, timeout: 5))
        }
        FileHandle.standardOutput.write(Data("UTTER_AUDIO_READY \(sample) \(Date().timeIntervalSince1970)\n".utf8))
        Thread.sleep(forTimeInterval: 12)
        if background { app.activate() }
        let started = Date()
        if !automaticStop { tapButton("voice.stop", down: true) }
        let result = app.staticTexts["voice.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 100), "Actual microphone audio must produce a transcript")
        print("DEVICE_SPEECH_RESULT \(sample) background=\(background) automatic=\(automaticStop) waitSeconds=\(Date().timeIntervalSince(started)) text=\(result.label)")
        capture("Physical recognized speech \(sample) background \(background)")
        let text = result.label.lowercased()
        for word in expected { XCTAssertTrue(text.contains(word), "Expected fixed sample keyword: \(word)") }
        XCTAssertFalse(app.buttons["voice.stop"].exists)
    }
}
