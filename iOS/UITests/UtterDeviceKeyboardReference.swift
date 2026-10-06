import XCTest

/// Reference capture of the system keyboard next to Utter's, for keyboard alignment work.
/// Output lines start with KBD_ and carry frames in points for scripts/ to compare.
extension UtterSimulatorFlow {
    func testDeviceKeyboardReferenceCapture() throws {
        let device = XCUIDevice.shared
        let originalAppearance = device.appearance
        addTeardownBlock {
            device.appearance = originalAppearance
            device.orientation = .portrait
            self.settings.terminate(); self.app.activate(); self.tapIfPresent("voice.disable"); self.app.terminate()
        }
        launchDeviceRelease()
        tapIfPresent("voice.disable")
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            for landscape in [false, true] {
                device.appearance = appearance
                device.orientation = landscape ? .landscapeLeft : .portrait
                Thread.sleep(forTimeInterval: 1.5)
                let tag = "\(appearance == .dark ? "dark" : "light")-\(landscape ? "landscape" : "portrait")"
                try openSettingsSearch()
                try showReferenceKeyboard(utter: false)
                try dumpReferenceKeyboard("native-\(tag)")
                try showReferenceKeyboard(utter: true)
                try dumpReferenceKeyboard("utter-\(tag)")
            }
        }
    }

    func showReferenceKeyboard(utter: Bool) throws {
        searchField.tap()
        // A custom keyboard is not exposed through `keyboards`; its status label is the marker.
        let deadline = Date().addingTimeInterval(10)
        while !settings.staticTexts["keyboard.status"].exists, !settings.keyboards.firstMatch.exists, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(settings.staticTexts["keyboard.status"].exists || settings.keyboards.firstMatch.exists, "No keyboard appeared")
        guard settings.staticTexts["keyboard.status"].exists != utter else { return }
        let globe = settings.buttons.matching(NSPredicate(
            format: "label IN %@ OR identifier == %@", ["Next keyboard", "下一个键盘", "切换键盘"], "keyboard.globe")).firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 5))
        globe.press(forDuration: 1)
        let table = settings.tables["InputSwitcherTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let cells = table.cells.allElementsBoundByIndex
        let labels = cells.map(\.label)
        print("KBD_INPUT_MODES \(labels)")
        let excluded = ["Utter", "Emoji", "表情", "Settings", "设置", "Handwriting", "手写"]
        let english = ["English", "英语", "英文"]
        let cell = utter
            ? cells.first { $0.label.hasPrefix("Utter") }
            : cells.first { cell in english.contains { cell.label.contains($0) } }
                ?? cells.first { cell in !excluded.contains { cell.label.contains($0) } }
        XCTAssertNotNil(cell, "No matching input mode in \(labels)")
        cell?.tap()
        XCTAssertEqual(settings.staticTexts["keyboard.status"].waitForExistence(timeout: 5), utter)
        Thread.sleep(forTimeInterval: 1)
    }

    private func dumpReferenceKeyboard(_ name: String) throws {
        let keyboard = settings.keyboards.firstMatch
        if name.hasPrefix("native"), !keyboard.waitForExistence(timeout: 5) {
            searchField.tap()
            XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        }
        let screen = settings.windows.firstMatch.frame
        print("KBD_SCREEN \(name) \(rectText(screen))")
        if keyboard.exists { print("KBD_FRAME \(name) \(rectText(keyboard.frame))") }
        for id in ["keyboard.globe", "keyboard.status", "keyboard.start", "keyboard.activate", "keyboard.delete", "keyboard.space", "keyboard.return"] {
            let element = settings.descendants(matching: .any)[id].firstMatch
            if element.exists { print("KBD_UTTER \(name) \(id) \(rectText(element.frame))") }
        }
        let lower = screen.height * 0.45
        func walk(_ node: XCUIElementSnapshot, depth: Int) {
            let frame = node.frame
            if frame.minY >= lower {
                print("KBD_ELEMENT \(name) d=\(depth) t=\(node.elementType.rawValue) id=\(node.identifier) label=\(node.label) frame=\(rectText(frame))")
            }
            node.children.forEach { walk($0, depth: depth + 1) }
        }
        walk(try settings.snapshot(), depth: 0)
        capture(name)
    }

    private func rectText(_ rect: CGRect) -> String {
        String(format: "%.1f,%.1f,%.1f,%.1f", rect.minX, rect.minY, rect.width, rect.height)
    }
}
