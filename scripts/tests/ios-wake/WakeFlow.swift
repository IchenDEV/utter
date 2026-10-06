import XCTest

@MainActor
final class UtterSimulatorFlow: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.ichendev.utter.ios")
    let host = XCUIApplication(bundleIdentifier: "com.ichendev.utter.wakehost")

    override func setUp() {
        continueAfterFailure = false
        app.terminate(); host.terminate()
    }

    override func tearDown() {
        capture("Final screen")
        let tree = XCTAttachment(string: app.debugDescription + "\n" + host.debugDescription)
        tree.name = "Final UI trees"; tree.lifetime = .keepAlways; add(tree)
        app.terminate(); host.terminate()
    }

    func testColdKeyboardLink() throws {
        host.launch()
        selectKeyboard()
        XCTAssertEqual(app.state, .notRunning, "Cold-start evidence requires a terminated main app")
        let link = host.descendants(matching: .any)["wake.link"].firstMatch
        let nonce = try XCTUnwrap(link.value as? String)
        XCTAssertNotNil(UUID(uuidString: nonce))
        capture("Cold keyboard before Link tap")
        link.tap()
        verifyCallback(nonce)
        capture("Cold main app after actual keyboard Link")
        try returnToOriginalField()
    }

    func testWarmKeyboardLink() throws {
        app.launch()
        let process = app.staticTexts["wake.process"].label
        let pid = app.staticTexts["wake.pid"].label
        host.launch()
        selectKeyboard()
        XCTAssertTrue(app.state == .runningBackground || app.state == .runningBackgroundSuspended)
        let link = host.descendants(matching: .any)["wake.link"].firstMatch
        let nonce = try XCTUnwrap(link.value as? String)
        capture("Warm keyboard before Link tap")
        link.tap()
        verifyCallback(nonce)
        XCTAssertEqual(app.staticTexts["wake.process"].label, process)
        XCTAssertEqual(app.staticTexts["wake.pid"].label, pid)
        capture("Warm main app after actual keyboard Link")
        try returnToOriginalField()
    }

    func testContainingAppURLControl() {
        host.launch()
        XCTAssertEqual(app.state, .notRunning)
        host.descendants(matching: .any)["host.control"].firstMatch.tap()
        verifyCallback("11111111-1111-4111-8111-111111111111")
        capture("Ordinary host Link positive URL control")
    }

    private func selectKeyboard() {
        host.textFields["host.first"].tap()
        if !host.descendants(matching: .any)["wake.link"].firstMatch.exists {
            let globe = host.buttons["Next keyboard"].firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5))
            globe.press(forDuration: 1)
            let utter = host.tables["InputSwitcherTable"].cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Utter,")).firstMatch
            XCTAssertTrue(utter.waitForExistence(timeout: 5)); utter.tap()
        }
        XCTAssertTrue(host.descendants(matching: .any)["wake.link"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(host.staticTexts["host.focus"].label, "first")
    }

    private func verifyCallback(_ nonce: String) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Link must actually bring the app foreground")
        XCTAssertTrue(app.staticTexts["wake.nonce"].waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "label == %@", nonce),
                               evaluatedWith: app.staticTexts["wake.nonce"])], timeout: 5)
        XCTAssertEqual(app.staticTexts["wake.nonce"].label, nonce)
        XCTAssertEqual(app.staticTexts["wake.scene"].label, "active")
        XCTAssertEqual(app.staticTexts["wake.count"].label, "1")
        XCTAssertGreaterThan(Int(app.staticTexts["wake.pid"].label) ?? 0, 0)
        XCTAssertFalse(app.staticTexts["wake.error"].exists)
        let receipt = XCTAttachment(string: "nonce=\(nonce)\nprocess=\(app.staticTexts["wake.process"].label)\npid=\(app.staticTexts["wake.pid"].label)\nscene=active\ncount=1")
        receipt.name = "Observed URL callback and main process"; receipt.lifetime = .keepAlways; add(receipt)
    }

    private func returnToOriginalField() throws {
        // A real breadcrumb tap is the return evidence; host.activate() would only prove automation can switch apps.
        // ponytail: iPhone Air/iOS 27 fixture only. The observed status-bar breadcrumb is outside the app AX tree.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 55, dy: 50)).tap()
        XCTAssertTrue(host.wait(for: .runningForeground, timeout: 5))
        XCTAssertEqual(host.staticTexts["host.focus"].label, "first")
        XCTAssertEqual(host.textFields["host.first"].value as? String, "Wake sample")
        XCTAssertEqual(host.textFields["host.second"].value as? String, "Other sample")
        XCTAssertTrue(host.descendants(matching: .any)["wake.link"].firstMatch.waitForExistence(timeout: 5))
        capture("Manual return with original field and keyboard")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
