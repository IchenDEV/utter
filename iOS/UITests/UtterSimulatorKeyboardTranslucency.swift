import XCTest

/// System keycaps are translucent: their colour follows what is behind the keyboard. One backdrop cannot tell
/// a translucent key from an opaque one of the same colour, so Utter's keys are compared with the system's
/// over two different backdrops (the simulator keeps the keyboard light while the app behind it turns dark).
extension UtterSimulatorFlow {
    func testKeyboardKeysAreTranslucentLikeTheSystemKeys() {
        continueAfterFailure = true
        let device = XCUIDevice.shared
        let original = device.appearance
        addTeardownBlock { device.appearance = original }
        let backdrops: [(tag: String, appearance: XCUIDevice.Appearance, color: String?)] = [
            ("light", .light, nil), ("dark", .dark, nil),
            ("light-red", .light, "0.85,0.10,0.10"), ("light-blue", .light, "0.10,0.25,0.85"),
            ("dark-green", .dark, "0.10,0.65,0.20"),
        ]
        var spread = 0
        var lightNative: [Int]?
        for backdrop in backdrops {
            device.appearance = backdrop.appearance
            app.terminate()
            app.launchArguments = app.launchArguments.filter { $0 != "--backdrop-color" && !$0.contains(",") }
            if let color = backdrop.color { app.launchArguments += ["--backdrop-color", color] }
            app.launch()
            Thread.sleep(forTimeInterval: 1.5)
            let field = app.textFields["field.first"]
            reveal(field); field.tap()
            showKeyboard(utter: false)
            let native = sampleKeys(utter: false)
            capture("native-\(backdrop.tag)")
            showKeyboard(utter: true)
            let utter = sampleKeys(utter: true)
            capture("utter-\(backdrop.tag)")
            print("KBD_TRANSLUCENCY \(backdrop.tag) native=\(native) utter=\(utter)")
            if let lightNative { spread = max(spread, zip(lightNative, native.keycap).map { abs($0 - $1) }.max() ?? 0) }
            else { lightNative = native.keycap }
            for channel in 0..<3 {
                XCTAssertLessThanOrEqual(abs(utter.keycap[channel] - native.keycap[channel]), 6,
                                         "keycap channel \(channel) over the \(backdrop.tag) backdrop: utter \(utter), system \(native)")
            }
        }
        XCTAssertGreaterThan(spread, 20, "The system keycap must change with the backdrop, otherwise this test proves nothing")
    }

    private func showKeyboard(utter: Bool) {
        let marker = app.staticTexts["keyboard.status"]
        if !marker.waitForExistence(timeout: 3) && !utter, app.keyboards.firstMatch.exists { return }
        if marker.exists == utter { return }
        let globe = app.buttons.matching(NSPredicate(format: "label IN %@ OR identifier == %@", ["Next keyboard", "下一个键盘"], "keyboard.globe")).firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 5))
        globe.press(forDuration: 1)
        let table = app.tables["InputSwitcherTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let cells = table.cells.allElementsBoundByIndex
        let cell = utter ? cells.first { $0.label.hasPrefix("Utter") }
                         : cells.first { $0.label.contains("English") || $0.label.contains("英") }
                           ?? cells.first { !$0.label.hasPrefix("Utter") && !$0.label.contains("Emoji") }
        XCTAssertNotNil(cell, "No input mode in \(cells.map(\.label))")
        cell?.tap()
        XCTAssertEqual(marker.waitForExistence(timeout: 5), utter)
        Thread.sleep(forTimeInterval: 1)
    }

    private func sampleKeys(utter: Bool) -> (keycap: [Int], backdrop: [Int]) {
        let space: CGRect
        if utter {
            let key = app.buttons["keyboard.space"]
            XCTAssertTrue(key.waitForExistence(timeout: 5)); space = key.frame
        } else {
            let key = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["space", "Space", "空格键"])).firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 5)); space = key.frame
        }
        let origin = utter ? space.origin : CGPoint(x: space.minX + 3, y: space.minY + 1)
        guard let shot = KeyboardScreenshot(landscape: false) else { XCTFail("no screenshot"); return ([0, 0, 0], [0, 0, 0]) }
        return (shot.color(origin.x + 60, origin.y + 8), shot.color(2, origin.y + 8))
    }
}
