import Foundation
import AppKit
import CoreGraphics
import Carbon.HIToolbox

enum InsertResult {
    case success
    case probablyFailed(reason: String)
}

@MainActor
struct TextInserter {
    func insert(text: String, targetApp: NSRunningApplication? = nil) async -> InsertResult {
        guard AXIsProcessTrusted() else {
            Log.error("[TextInserter] no AX trust")
            return .probablyFailed(reason: "Accessibility permission not granted")
        }

        await activateTarget(targetApp)

        let front = NSWorkspace.shared.frontmostApplication
        let targetPID = targetApp?.processIdentifier
        let activated = targetPID == nil || front?.processIdentifier == targetPID

        let result = await insertViaClipboard(text: text)

        if !activated || !result {
            let reason = activated
                ? "Paste command may not have reached the target"
                : "Could not activate target application"
            Log.info("[TextInserter] probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }
        return .success
    }

    func replaceRecentInsertion(
        text: String,
        previouslyInserted: String? = nil,
        targetApp: NSRunningApplication? = nil
    ) async -> InsertResult {
        if let failure = await prepareTargetOperation(targetApp: targetApp, logContext: "replacement") {
            return failure
        }

        if let previouslyInserted {
            let beforeCaret = focusedTextBeforeCaret(maxUTF16Length: previouslyInserted.utf16.count + 8)
            let safe = RecentInsertionGuard.isReplacementSafe(
                textBeforeCaret: beforeCaret,
                inserted: previouslyInserted
            )
            if safe == false {
                let reason = L("pipeline.replacement_reason_text_changed")
                Log.info("[TextInserter] replacement skipped: caret text changed since insertion")
                return .probablyFailed(reason: reason)
            }
        }

        let undoOK = await simulateCommandShortcut(keyCode: CGKeyCode(kVK_ANSI_Z), scriptKey: "z")
        guard undoOK else {
            let reason = "Could not undo the previous insertion"
            Log.info("[TextInserter] replacement probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }

        try? await Task.sleep(nanoseconds: 160_000_000)

        let pasted = await insertViaClipboard(text: text)
        guard pasted else {
            let reason = "Could not paste replacement text"
            Log.info("[TextInserter] replacement probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }

        return .success
    }

    func undoRecentInsertion(targetApp: NSRunningApplication? = nil) async -> InsertResult {
        if let failure = await prepareTargetOperation(targetApp: targetApp, logContext: "undo") {
            return failure
        }

        let undoOK = await simulateCommandShortcut(keyCode: CGKeyCode(kVK_ANSI_Z), scriptKey: "z")
        guard undoOK else {
            let reason = "Could not undo the previous insertion"
            Log.info("[TextInserter] undo probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }

        return .success
    }

    func replaceSelectedText(text: String, targetApp: NSRunningApplication? = nil) async -> InsertResult {
        if let failure = await prepareSelectedTextOperation(
            targetApp: targetApp,
            logContext: "selection replacement"
        ) {
            return failure
        }

        let pasted = await insertViaClipboard(text: text)
        guard pasted else {
            let reason = "Could not paste replacement text"
            Log.info("[TextInserter] selection replacement probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }

        return .success
    }

    func deleteSelectedText(targetApp: NSRunningApplication? = nil) async -> InsertResult {
        if let failure = await prepareSelectedTextOperation(
            targetApp: targetApp,
            logContext: "selection deletion"
        ) {
            return failure
        }

        let deleted = await simulateKeyPress(keyCode: CGKeyCode(kVK_Delete), scriptKeyCode: 51)
        guard deleted else {
            let reason = "Could not delete selected text"
            Log.info("[TextInserter] selection deletion probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }

        return .success
    }

    func selectedText(targetApp: NSRunningApplication? = nil) async -> String? {
        guard AXIsProcessTrusted() else {
            Log.error("[TextInserter] no AX trust")
            return nil
        }

        await activateTarget(targetApp)
        return selectedTextInFrontmostApplication()
    }

    // MARK: - Activate target

    private func activateTarget(_ app: NSRunningApplication?) async {
        guard let app, !app.isTerminated else { return }

        NSApp.yieldActivation(to: app)
        app.activate()

        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                break
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    private func selectedTextInFrontmostApplication() -> String? {
        guard let focusedElement = focusedElementInFrontmostApplication() else { return nil }

        var selectedValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        guard selectedResult == .success else { return nil }

        return selectedValue as? String
    }

    private func focusedElementInFrontmostApplication() -> AXUIElement? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(front.processIdentifier)

        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedResult == .success, let focusedElement = focusedValue else { return nil }
        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }
        return (focusedElement as! AXUIElement)
    }

    /// Reads the focused element's text up to the caret (end of selection).
    /// Returns nil when the app does not expose value/selection via AX.
    private func focusedTextBeforeCaret(maxUTF16Length: Int) -> String? {
        guard let focusedElement = focusedElementInFrontmostApplication() else { return nil }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }
        var selectedRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange) else { return nil }

        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
            let fullText = textValue as? String else {
            return nil
        }

        let caret = min(max(0, selectedRange.location + selectedRange.length), fullText.utf16.count)
        let start = max(0, caret - maxUTF16Length)
        let utf16 = fullText.utf16
        guard let startIndex = utf16.index(utf16.startIndex, offsetBy: start, limitedBy: utf16.endIndex),
              let caretIndex = utf16.index(utf16.startIndex, offsetBy: caret, limitedBy: utf16.endIndex),
              let lower = String.Index(startIndex, within: fullText),
              let upper = String.Index(caretIndex, within: fullText) else {
            return nil
        }
        return String(fullText[lower..<upper])
    }

    private func prepareSelectedTextOperation(
        targetApp: NSRunningApplication?,
        logContext: String
    ) async -> InsertResult? {
        if let failure = await prepareTargetOperation(targetApp: targetApp, logContext: logContext) {
            return failure
        }

        guard selectedTextInFrontmostApplication()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            let reason = L("pipeline.no_selected_text_to_replace")
            Log.info("[TextInserter] \(logContext) probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }

        return nil
    }

    private func prepareTargetOperation(
        targetApp: NSRunningApplication?,
        logContext: String
    ) async -> InsertResult? {
        guard AXIsProcessTrusted() else {
            Log.error("[TextInserter] no AX trust")
            return .probablyFailed(reason: "Accessibility permission not granted")
        }

        await activateTarget(targetApp)

        let front = NSWorkspace.shared.frontmostApplication
        let targetPID = targetApp?.processIdentifier
        let activated = targetPID == nil || front?.processIdentifier == targetPID
        guard activated else {
            let reason = "Could not activate target application"
            Log.info("[TextInserter] \(logContext) probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }

        return nil
    }

    // MARK: - Clipboard + Cmd+V

    /// Returns true if at least one paste method was executed without errors.
    private func insertViaClipboard(text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let prevChange = pasteboard.changeCount
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try? await Task.sleep(nanoseconds: 50_000_000)

        let pasteOK: Bool
        if await simulatePaste() {
            pasteOK = true
        } else {
            Log.info("[TextInserter] CGEvent failed, trying AppleScript")
            pasteOK = pasteViaAppleScript()
        }

        try? await Task.sleep(nanoseconds: 300_000_000)

        if pasteboard.changeCount == prevChange + 1 {
            pasteboard.clearContents()
            if let prev = previousContents {
                pasteboard.setString(prev, forType: .string)
            }
        }

        return pasteOK
    }

    /// Place text on the clipboard so the user can manually Cmd+V.
    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
