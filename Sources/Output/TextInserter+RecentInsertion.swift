import AppKit
import Carbon.HIToolbox
import Foundation

struct RecentInsertionAnchor {
    let processIdentifier: pid_t
    let element: AXUIElement
    let range: NSRange
    let text: String
}

@MainActor
extension TextInserter {
    func replaceRecentInsertion(
        text: String,
        previouslyInserted: String,
        targetApp: NSRunningApplication? = nil
    ) async -> InsertResult {
        if let failure = await prepareTargetOperation(targetApp: targetApp, logContext: "replacement") {
            return failure
        }
        guard selectRecentInsertion(expectedText: previouslyInserted) else {
            let reason = L("pipeline.replacement_reason_text_changed")
            Log.info("[TextInserter] replacement skipped: insertion target changed")
            return .probablyFailed(reason: reason)
        }

        let pasted = await insertViaClipboard(text: text)
        guard pasted else {
            forgetRecentInsertion()
            let reason = "Could not paste replacement text"
            Log.info("[TextInserter] replacement probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }

        rememberRecentInsertion(text: text)
        return .success
    }

    func undoRecentInsertion(
        previouslyInserted: String,
        targetApp: NSRunningApplication? = nil
    ) async -> InsertResult {
        if let failure = await prepareTargetOperation(targetApp: targetApp, logContext: "undo") {
            return failure
        }
        guard selectRecentInsertion(expectedText: previouslyInserted) else {
            let reason = L("pipeline.replacement_reason_text_changed")
            Log.info("[TextInserter] undo skipped: insertion target changed")
            return .probablyFailed(reason: reason)
        }

        let deleted = await simulateKeyPress(keyCode: CGKeyCode(kVK_Delete), scriptKeyCode: 51)
        guard deleted else {
            let reason = "Could not delete the previous insertion"
            Log.info("[TextInserter] undo probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }

        forgetRecentInsertion()
        return .success
    }

    func rememberRecentInsertion(text: String) {
        guard !text.isEmpty,
              let front = NSWorkspace.shared.frontmostApplication,
              let element = focusedElementInFrontmostApplication(),
              let selection = selectedRange(of: element),
              selection.length == 0,
              let currentText = value(of: element) else {
            recentInsertionAnchor = nil
            return
        }

        let insertedRange = NSRange(
            location: selection.location - text.utf16.count,
            length: text.utf16.count
        )
        guard RecentInsertionGuard.isReplacementSafe(
            sameTarget: true,
            currentSelection: selection,
            insertedRange: insertedRange,
            currentText: currentText,
            inserted: text
        ) else {
            recentInsertionAnchor = nil
            return
        }

        recentInsertionAnchor = RecentInsertionAnchor(
            processIdentifier: front.processIdentifier,
            element: element,
            range: insertedRange,
            text: text
        )
    }

    func forgetRecentInsertion() {
        recentInsertionAnchor = nil
    }
}

private extension TextInserter {
    func selectRecentInsertion(expectedText: String) -> Bool {
        guard let anchor = recentInsertionAnchor,
              anchor.text == expectedText,
              let front = NSWorkspace.shared.frontmostApplication,
              let element = focusedElementInFrontmostApplication(),
              let selection = selectedRange(of: element),
              let currentText = value(of: element) else {
            return false
        }

        let sameTarget = front.processIdentifier == anchor.processIdentifier
            && CFEqual(element, anchor.element)
        guard RecentInsertionGuard.isReplacementSafe(
            sameTarget: sameTarget,
            currentSelection: selection,
            insertedRange: anchor.range,
            currentText: currentText,
            inserted: expectedText
        ) else {
            return false
        }

        var range = CFRange(location: anchor.range.location, length: anchor.range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        ) == .success
    }

    func selectedRange(of element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range),
              range.location >= 0,
              range.length >= 0 else {
            return nil
        }
        return NSRange(location: range.location, length: range.length)
    }

    func value(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }
}
