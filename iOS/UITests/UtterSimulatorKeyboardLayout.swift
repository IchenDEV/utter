import XCTest

/// Layout checks for the product keyboard that need no speech: the editing keys stay reachable inside the
/// screen in both orientations, at whatever text size the system is set to (`xcrun simctl ui … content_size`).
extension UtterSimulatorFlow {
    func testProductKeyboardLayoutPortrait() { checkKeyboardLayout(.portrait) }
    func testProductKeyboardLayoutLandscape() { checkKeyboardLayout(.landscapeLeft) }

    private func checkKeyboardLayout(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        defer { XCUIDevice.shared.orientation = .portrait }
        let category = UIScreen.main.traitCollection.preferredContentSizeCategory
        let field = app.textFields["field.first"]
        revealGently(field); field.tap(); selectUtterKeyboard()
        XCTAssertTrue(app.staticTexts["keyboard.status"].waitForExistence(timeout: 5))
        let screen = app.windows.firstMatch.frame
        let keys = ["globe", "space", "return", "delete"].map { app.buttons["keyboard.\($0)"] }
        for key in keys {
            XCTAssertTrue(key.waitForExistence(timeout: 5), "\(key.identifier) missing")
            XCTAssertTrue(key.isHittable, "\(key.identifier) must be reachable")
            XCTAssertGreaterThanOrEqual(key.frame.height, 36, key.identifier)
            XCTAssertLessThanOrEqual(key.frame.maxY, screen.maxY + 0.5, "\(key.identifier) sits below the screen")
            XCTAssertGreaterThanOrEqual(key.frame.minX, screen.minX - 4, key.identifier)
            XCTAssertLessThanOrEqual(key.frame.maxX, screen.maxX + 4, key.identifier)
        }
        let globe = keys[0].frame, space = keys[1].frame, ret = keys[2].frame, delete = keys[3].frame
        XCTAssertLessThan(globe.minX, space.minX, "The globe is the leftmost bottom-row key")
        XCTAssertLessThan(space.minX, ret.minX, "Return is the rightmost bottom-row key")
        XCTAssertEqual(globe.midY, space.midY, accuracy: 6, "Globe and space share the bottom row")
        if category.isAccessibilityCategory {
            // Large text swaps the grid for a scrolling area above a fixed bottom row; the action must stay reachable.
            capture("Product keyboard layout \(orientation.rawValue) \(category.rawValue) before scrolling")
            // Without Full Access there is no activation action to reach.
            let activate = app.descendants(matching: .any)["keyboard.activate"].firstMatch
            let area = app.scrollViews.containing(.staticText, identifier: "keyboard.status").firstMatch
            if activate.exists {
                for _ in 0..<3 where !activate.isHittable { area.swipeUp() }
                XCTAssertTrue(activate.isHittable, "The activation action must be reachable at large text sizes")
            }
        } else {
            XCTAssertLessThan(delete.maxY, space.minY, "Delete sits in the top row, above the bottom row")
        }
        capture("Product keyboard layout \(orientation.rawValue) \(category.rawValue)")
    }

    /// A swipe in a short landscape window scrolls past the field; a short slow drag moves by its own travel only.
    private func revealGently(_ element: XCUIElement) {
        let content = app.collectionViews.matching(NSPredicate(format: "label != %@", "Sidebar")).firstMatch
        let start = content.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.75))
        let end = content.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6))
        for _ in 0..<40 where !element.isHittable {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
    }
}
