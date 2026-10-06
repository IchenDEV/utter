import XCTest

extension UtterSimulatorFlow {
    func testDeviceSafariSampleBufferVideoBeforeStandby() async throws {
        try await testDeviceSafariNoAudioVideoBeforeStandby()
    }

    func testDeviceSafariSampleBufferVideoAfterStandby() async throws {
        try await testDeviceSafariNoAudioVideoAfterStandby()
    }

    func testDeviceSafariAudioActivationControl() async throws {
        try await openSafariFixture()
        try await startSafariVideo()
        let before = try videoPosition()
        app.activate()
        app.buttons["probe.pip"].tap()
        XCTAssertTrue(app.staticTexts["audio-control"].waitForExistence(timeout: 10))
        host.activate()
        try await Task.sleep(for: .seconds(10))
        XCTAssertGreaterThan(try videoPosition(), before + 8)
        capture("Mixing audio activation without Utter PiP")
    }

    func testDeviceSafariNoAudioVideoBeforeStandby() async throws {
        try await openSafariFixture()
        try await startSafariVideo()
        let before = try videoPosition()
        app.activate()
        try startSafariStandby()
        host.activate()
        try await Task.sleep(for: .seconds(10))
        XCTAssertGreaterThan(try videoPosition(), before + 8)
        capture("Content source video-first coexistence")
        try await verifyStandbySurvived()
    }

    func testDeviceSafariNoAudioVideoAfterStandby() async throws {
        try startSafariStandby()
        try await openSafariFixture()
        try await startSafariVideo()
        let before = try videoPosition()
        try await Task.sleep(for: .seconds(10))
        XCTAssertGreaterThan(try videoPosition(), before + 8)
        try await verifyStandbySurvived()
    }

    private func verifyStandbySurvived() async throws {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        try await Task.sleep(for: .seconds(1))
        let state = app.staticTexts["probe.resumed_pip"].label
        print("REAL_STANDBY resumedPiP=\(state) phase=\(app.staticTexts["probe.status"].label)")
        capture("Content source standby state after external PiP")
        XCTAssertTrue(["active", "suspended"].contains(state), "Record suspended separately; it does not prove background execution")
        XCTAssertEqual(app.staticTexts["probe.status"].label, "active")
    }

    func testRealSafariCleanupRetiredFixtures() async throws {
        host.activate()
        // IDs from this device run's failed HTTP/navigation fixtures only.
        for id in ["13BC66EC-BC84-4968-802C-6B4954C5E0C0", "5832EDEC-8A5C-412C-80D1-32C2D6FF587B", "B760FD1B-56FC-4A04-869A-018A9BD86508", "34AA48DD-B9A4-4299-91FF-D10F6CAF8B87"] {
            safariTabID = id
            try await cleanupSafariFixture()
            XCTAssertFalse(host.descendants(matching: .any).matching(NSPredicate(format:
                "(identifier BEGINSWITH %@ OR identifier BEGINSWITH %@) AND identifier CONTAINS %@",
                "TabBarTab?", "TabDocument?", "UUID=\(id)&")).firstMatch.exists)
        }
        safariTabID = nil
    }

    func testRealSafariExternalVideoAfterStandby() async throws {
        try startSafariStandby()
        try await openSafariFixture()
        try await startSafariVideo()
        try await verifySafariSpeech()
    }

    func testRealSafariExternalVideoBeforeStandby() async throws {
        try await openSafariFixture()
        try await startSafariVideo()
        app.activate()
        try startSafariStandby()
        host.activate()
        try await verifySafariSpeech()
    }

    func testRealSafariVideoControl() async throws {
        try await openSafariFixture()
        try await startSafariVideo()
        let before = try videoPosition()
        app.activate()
        try await Task.sleep(for: .seconds(2))
        host.activate()
        try await Task.sleep(for: .seconds(15))
        XCTAssertGreaterThan(try videoPosition(), before + 10)
        capture("Safari video PiP control without standby")
    }

    private func startSafariStandby() throws {
        app.buttons["probe.pip"].tap()
        XCTAssertTrue(app.staticTexts["active"].waitForExistence(timeout: 30))
    }

    private func openSafariFixture() async throws {
        host.activate()
        XCTAssertTrue(host.wait(for: .runningForeground, timeout: 5))
        try await Task.sleep(for: .seconds(2))
        if !host.buttons["NewTabButton"].isHittable, host.buttons["Stop video"].exists {
            // Dismiss the test page's address popover using its empty lower-right margin.
            host.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.9)).tap()
        }
        capture("Safari foreground before opening fixed fixture")
        let tabs = host.descendants(matching: .any).matching(NSPredicate(format:
            "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@", "TabBarTab?", "TabDocument?"))
        let existing = Set(tabs.allElementsBoundByIndex.compactMap { tabID($0) })
        let tab = host.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "TabBarTab?isActive=true")).firstMatch
        for _ in 0..<2 {
            // Safari's address popover makes AX report no hit point for the visible + button.
            host.buttons["NewTabButton"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            try await Task.sleep(for: .seconds(1))
            if tab.exists, let created = tabID(tab), !existing.contains(created) { break }
        }
        let created = try XCTUnwrap(tabID(tab))
        guard !existing.contains(created) else {
            XCTFail("New test tab did not open; existing tabs must not be edited or closed")
            throw NSError(domain: "StandbySafari", code: 1)
        }
        safariTabID = created
        tab.textFields.firstMatch.tap()
        // Safari replaces the address-field element when editing begins.
        host.typeText("http://192.168.31.154:8766/\n")
        try await Task.sleep(for: .seconds(3))
        if host.staticTexts["此连接不安全"].waitForExistence(timeout: 5) {
            let proceed = host.buttons["继续"]
            if proceed.exists { proceed.tap() } // Only the fixed local HTTP fixture.
        }
        XCTAssertTrue(host.buttons["Play video"].waitForExistence(timeout: 30))
    }

    private func tabID(_ tab: XCUIElement) -> String? {
        guard tab.identifier.contains("UUID=") else { return nil }
        return tab.identifier.components(separatedBy: "UUID=").last?.components(separatedBy: "&").first
    }

    private func startSafariVideo() async throws {
        host.buttons["Play video"].tap()
        try await Task.sleep(for: .seconds(3))
        XCTAssertGreaterThan(try videoPosition(requirePiP: false), 0.5, "Video must play before requesting PiP")
        host.buttons["Start video PiP"].tap()
        try await Task.sleep(for: .seconds(3))
        _ = try videoPosition()
        capture("External Safari video PiP")
    }

    private func videoPosition(requirePiP: Bool = true) throws -> Double {
        let state = host.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Video:'")).firstMatch.label
        print("REAL_STANDBY externalVideo=\(state)")
        if (requirePiP && !state.contains("picture-in-picture")) || !state.contains("paused=false") {
            capture("External video state check failed")
        }
        if requirePiP { XCTAssertTrue(state.contains("picture-in-picture")) }
        XCTAssertTrue(state.contains("paused=false"))
        return try XCTUnwrap(Double(state.components(separatedBy: "time=").last?.components(separatedBy: " ").first ?? ""))
    }

    private func verifySafariSpeech() async throws {
        let before = try videoPosition()
        selectKeyboard()
        try await dictateReal()
        XCTAssertGreaterThan(try videoPosition(), before + 10, "External video must actually advance")
        capture("External Safari video after actual speech insertion")
    }

    func cleanupSafariFixture() async throws {
        guard let safariTabID else { return }
        host.activate()
        guard host.wait(for: .runningForeground, timeout: 5) else { return }
        try await Task.sleep(for: .seconds(1))
        let tab = host.buttons.matching(NSPredicate(format: "identifier CONTAINS %@", "UUID=\(safariTabID)&")).firstMatch
        if tab.exists {
            if !tab.identifier.contains("isActive=true") { tab.tap() }
            guard tab.identifier.contains("isActive=true") else { return }
            if host.buttons["Stop video"].exists { host.buttons["Stop video"].tap() }
            let close = host.buttons.matching(identifier: "CloseTabBarItemButton")
            guard close.count == 1 else { capture("Known fixture cleanup unavailable"); return }
            close.firstMatch.tap()
        }
    }
}
