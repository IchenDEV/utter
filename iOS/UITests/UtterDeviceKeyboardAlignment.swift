import XCTest

/// Compares Utter's keyboard with the system keyboard in one run and asserts the alignment promises in
/// docs/sdlc/changes/2026-10-06-keyboard-native-alignment/intent.md (iPad mini is the acceptance device).
extension UtterSimulatorFlow {
    private struct KeyboardProbe {
        var bar: CGRect
        var globe: CGRect
        var delete: CGRect
        var space: CGRect
        var colors: [String: [Int]]
        var corner: CGFloat
    }

    func testDeviceKeyboardNativeAlignment() throws {
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
                let native = probe(utter: false, tag: tag, landscape: landscape)
                try showReferenceKeyboard(utter: true)
                let utter = probe(utter: true, tag: tag, landscape: landscape)
                compare(native, utter, tag: tag)
            }
        }
    }

    private func probe(utter: Bool, tag: String, landscape: Bool) -> KeyboardProbe {
        func frame(_ element: XCUIElement, _ what: String) -> CGRect {
            XCTAssertTrue(element.waitForExistence(timeout: 5), "\(what) missing in \(tag)")
            return element.frame
        }
        func find(_ id: String) -> XCUIElement { settings.descendants(matching: .any)[id].firstMatch }
        capture("\(utter ? "utter" : "native")-\(tag)")
        let spaceLabels = ["空格键", "space", "Space"]
        let nativeSpace = settings.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", spaceLabels)).firstMatch
        let bar = frame(find("SystemInputAssistantView"), "assistant bar")
        let globe = frame(find(utter ? "keyboard.globe" : "emoji"), "globe")
        let delete = frame(find(utter ? "keyboard.delete" : "delete"), "delete")
        let space = frame(utter ? find("keyboard.space") : nativeSpace, "space")
        // System key frames reach 3pt left of the visible key and 1pt above it; Utter's space frame is the visible key.
        let key = utter ? space.origin : CGPoint(x: space.minX + 3, y: space.minY + 1)
        var colors: [String: [Int]] = [:]
        var corner: CGFloat = 0
        if let shot = KeyboardScreenshot(landscape: landscape) {
            colors = ["backdrop": shot.color(2, bar.maxY + 8 + 64.5 + 27), "keycap": shot.color(key.x + 60, key.y + 8)]
            corner = shot.cornerInset(left: key.x, top: key.y)
        }
        print("KBD_PROBE \(utter ? "utter" : "native")-\(tag) bar=\(bar) globe=\(globe) delete=\(delete) space=\(space) colors=\(colors) corner=\(corner)")
        return KeyboardProbe(bar: bar, globe: globe, delete: delete, space: space, colors: colors, corner: corner)
    }

    private func compare(_ native: KeyboardProbe, _ utter: KeyboardProbe, tag: String) {
        func near(_ a: CGFloat, _ b: CGFloat, _ what: String, tolerance: CGFloat = 2) {
            XCTAssertEqual(a, b, accuracy: tolerance, "\(what) differs from the system keyboard in \(tag): utter \(a), system \(b)")
        }
        near(utter.bar.minY, native.bar.minY, "keyboard top")
        near(utter.globe.minX, native.globe.minX, "globe left edge")
        near(utter.globe.midY, native.globe.midY, "globe vertical centre")
        near(utter.globe.maxY, native.globe.maxY, "globe bottom")
        near(utter.delete.minX, native.delete.minX + 3, "delete left edge")
        near(utter.delete.midY, native.delete.minY + 1 + utter.delete.height / 2, "delete vertical centre")
        near(utter.space.minY, native.space.minY + 1, "bottom row top")
        near(utter.corner, native.corner, "key corner curve", tolerance: 1)
        for (name, system) in native.colors {
            guard let mine = utter.colors[name] else { continue }
            let limit = name == "keycap" ? 6 : 8
            for channel in 0..<3 {
                XCTAssertLessThanOrEqual(abs(mine[channel] - system[channel]), limit,
                                         "\(name) colour channel \(channel) in \(tag): utter \(mine), system \(system)")
            }
        }
    }
}
