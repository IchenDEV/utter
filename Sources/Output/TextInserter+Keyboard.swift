import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

@MainActor
extension TextInserter {
    @discardableResult
    func simulatePaste() async -> Bool {
        await simulateCommandShortcut(keyCode: CGKeyCode(kVK_ANSI_V), scriptKey: "v")
    }

    @discardableResult
    func simulateCommandShortcut(keyCode: CGKeyCode, scriptKey: String) async -> Bool {
        guard !Task.isCancelled, AXIsProcessTrusted() else { return false }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return simulateCommandShortcutViaAppleScript(scriptKey)
        }

        keyDown.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        try? await Task.sleep(nanoseconds: 12_000_000)
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        return true
    }

    @discardableResult
    func simulateKeyPress(keyCode: CGKeyCode, scriptKeyCode: Int) async -> Bool {
        guard !Task.isCancelled, AXIsProcessTrusted() else { return false }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return simulateKeyPressViaAppleScript(scriptKeyCode)
        }

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        try? await Task.sleep(nanoseconds: 12_000_000)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        return true
    }

    func pasteViaAppleScript() -> Bool {
        simulateCommandShortcutViaAppleScript("v")
    }
}

private extension TextInserter {
    func simulateKeyPressViaAppleScript(_ keyCode: Int) -> Bool {
        let script = NSAppleScript(source: """
        tell application "System Events" to key code \(keyCode)
        """)
        var errInfo: NSDictionary?
        script?.executeAndReturnError(&errInfo)
        if let errInfo {
            Log.error("[TextInserter] AppleScript error: \(errInfo)")
            return false
        }
        return true
    }

    func simulateCommandShortcutViaAppleScript(_ key: String) -> Bool {
        let script = NSAppleScript(source: """
        tell application "System Events" to keystroke "\(key)" using command down
        """)
        var errInfo: NSDictionary?
        script?.executeAndReturnError(&errInfo)
        if let errInfo {
            Log.error("[TextInserter] AppleScript error: \(errInfo)")
            return false
        }
        return true
    }
}
