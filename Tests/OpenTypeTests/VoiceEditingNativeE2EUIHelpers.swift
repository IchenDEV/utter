import AppKit
import Foundation
import XCTest
import UtterContracts
import UtterPresentationContracts
@testable import UtterPresentation

@MainActor
enum NativeE2EUI {
    static func directory(override: String? = ProcessInfo.processInfo.environment["UTTER_NATIVE_EVIDENCE"]) throws -> URL {
        let directory = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? TestFixtureRoot.root.appendingPathComponent("NativeEvidence", isDirectory: true)
        for name in ["logs", "screenshots"] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true
            )
        }
        return directory
    }

    static func panel() throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.nonactivatingPanel) })
    }

    static func capture(_ name: String, window: NSWindow) async throws {
        try await Task.sleep(for: .milliseconds(250))
        let view = try XCTUnwrap(window.contentView)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory().appendingPathComponent("screenshots/" + name + ".png"))
        try record(name, ["windowNumber": window.windowNumber, "frame": NSStringFromRect(window.frame),
            "key": window.isKeyWindow, "active": NSApp.isActive, "accessibility": labels(view)])
    }

    static func labels(_ object: Any, depth: Int = 0) -> [[String: String]] {
        guard depth < 18, let node = object as? NSAccessibilityProtocol else { return [] }
        var result: [[String: String]] = []
        if let role = node.accessibilityRole() {
            result.append(["role": role.rawValue, "label": node.accessibilityLabel() ?? "",
                "value": String(describing: node.accessibilityValue() ?? "")])
        }
        for child in node.accessibilityChildren() ?? [] { result += labels(child, depth: depth + 1) }
        return result
    }

    static func button(_ object: Any, label: String, depth: Int = 0) -> (any NSAccessibilityProtocol)? {
        guard depth < 18, let node = object as? NSAccessibilityProtocol else { return nil }
        if node.accessibilityRole() == .button, node.accessibilityLabel() == label { return node }
        for child in node.accessibilityChildren() ?? [] {
            if let found = button(child, label: label, depth: depth + 1) { return found }
        }
        return nil
    }

    static func pointer(_ label: String, in window: NSWindow) async throws {
        try await NativeSelectionReviewTestSupport.activateAccessibility(in: window)
        let button = try NativeSelectionReviewTestSupport.button(label, in: window)
        NativeSelectionReviewTestSupport.assertVisible(button, in: window)
        let frame = button.accessibilityFrame()
        let location = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
        try record("local-pointer-" + label, ["windowNumber": window.windowNumber,
            "x": location.x, "y": location.y, "locator": "current localized control AX frame converted to owned window",
            "systemPointerPosted": false])
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    static func ax(_ action: String, label: String) async throws -> [String: Any] {
        let task = Process()
        task.executableURL = try directory().appendingPathComponent("fixtures/owned-ax-client")
        task.arguments = [String(ProcessInfo.processInfo.processIdentifier), action, label]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while task.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        if task.isRunning { task.terminate(); throw NSError(domain: "OwnedAXClientTimeout", code: 1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        try data.write(to: directory().appendingPathComponent("logs/ax-\(action)-\(label).json"))
        XCTAssertEqual(task.terminationStatus, 0, String(decoding: data, as: UTF8.self))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func localKey(_ code: UInt16, character: String, in window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code))
        window.sendEvent(event)
    }

    static func record(_ name: String, _ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory().appendingPathComponent("logs/" + name + ".json"))
    }
}

struct NativeE2EDiagnostics: DiagnosticsService {
    func info(_ message: String) {}
    func sensitive(_ message: String) {}
    func error(_ message: String) {}
}
