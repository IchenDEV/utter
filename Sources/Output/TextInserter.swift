import Foundation
import AppKit
import CoreGraphics
import Carbon.HIToolbox

enum InsertResult {
    case success
    case probablyFailed(reason: String)
}

@MainActor
final class TextInserter {
    var recentInsertionAnchor: RecentInsertionAnchor?

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
            forgetRecentInsertion()
            let reason = activated
                ? "Paste command may not have reached the target"
                : "Could not activate target application"
            Log.info("[TextInserter] probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }
        rememberRecentInsertion(text: text)
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

        rememberRecentInsertion(text: text)
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

        forgetRecentInsertion()
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

    func focusedElementInFrontmostApplication() -> AXUIElement? {
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

    func prepareTargetOperation(
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
    func insertViaClipboard(text: String) async -> Bool {
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
