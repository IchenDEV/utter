import UtterContracts
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

@MainActor
extension TextInserter {
    @discardableResult
    package func simulatePaste() async -> Bool {
        await simulateCommandShortcut(keyCode: CGKeyCode(kVK_ANSI_V), scriptKey: "v")
    }

    @discardableResult
    package func simulateCommandShortcut(keyCode: CGKeyCode, scriptKey: String) async -> Bool {
        guard !Task.isCancelled, canCommit(), AXIsProcessTrusted() else { return false }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return simulateCommandShortcutViaAppleScript(scriptKey)
        }

        guard canCommit(), commitEffect?(.paste) ?? true else { return false }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        try? await Task.sleep(nanoseconds: 12_000_000)
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        return true
    }

    @discardableResult
    package func simulateKeyPress(keyCode: CGKeyCode, scriptKeyCode: Int) async -> Bool {
        guard !Task.isCancelled, canCommit(), AXIsProcessTrusted() else { return false }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return simulateKeyPressViaAppleScript(scriptKeyCode)
        }

        guard canCommit(), commitEffect?(.keyPress) ?? true else { return false }
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        try? await Task.sleep(nanoseconds: 12_000_000)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        return true
    }

    package func pasteViaAppleScript() -> Bool {
        simulateCommandShortcutViaAppleScript("v")
    }
}

private extension TextInserter {
    func simulateKeyPressViaAppleScript(_ keyCode: Int) -> Bool {
        let script = NSAppleScript(source: """
        tell application "System Events" to key code \(keyCode)
        """)
        var errInfo: NSDictionary?
        guard let script, canCommit(), commitEffect?(.keyPress) ?? true else { return false }
        script.executeAndReturnError(&errInfo)
        if let errInfo {
            log.error("[TextInserter] AppleScript error: \(errInfo)")
            return false
        }
        return true
    }

    func simulateCommandShortcutViaAppleScript(_ key: String) -> Bool {
        let script = NSAppleScript(source: """
        tell application "System Events" to keystroke "\(key)" using command down
        """)
        var errInfo: NSDictionary?
        guard let script, canCommit(), commitEffect?(.paste) ?? true else { return false }
        script.executeAndReturnError(&errInfo)
        if let errInfo {
            log.error("[TextInserter] AppleScript error: \(errInfo)")
            return false
        }
        return true
    }
}
