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
    #if DEBUG
    var insertOverrideForTesting: ((String) -> InsertResult)?
    #endif

    func insert(text: String, targetApp: NSRunningApplication? = nil) async -> InsertResult {
        guard !Task.isCancelled else { return .probablyFailed(reason: L("error.operation_failed")) }
        #if DEBUG
        if let insertOverrideForTesting { return insertOverrideForTesting(text) }
        #endif
        guard AXIsProcessTrusted() else {
            Log.error("[TextInserter] no AX trust")
            return .probablyFailed(reason: "Accessibility permission not granted")
        }

        await activateTarget(targetApp)
        guard !Task.isCancelled else { return .probablyFailed(reason: L("error.operation_failed")) }

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
        guard !Task.isCancelled else { return }
        guard let app, !app.isTerminated else { return }

        NSApp.yieldActivation(to: app)
        app.activate()

        for _ in 0..<30 {
            guard !Task.isCancelled else { return }
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
        guard !Task.isCancelled else { return .probablyFailed(reason: L("error.operation_failed")) }

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
    func insertViaClipboard(
        text: String,
        pasteboard: NSPasteboard = .general,
        paste: (() async -> Bool)? = nil
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        let previousItems = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let insertedChange = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == insertedChange {
                pasteboard.clearContents()
                pasteboard.writeObjects(previousItems)
            }
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        guard !Task.isCancelled else { return false }
        let pasteOK: Bool
        if let paste {
            pasteOK = await paste()
        } else {
            pasteOK = await performPaste()
        }
        if pasteOK {
            // A posted key cannot be recalled. Let the target read the clipboard
            // before restoring it, even when the caller cancels after posting.
            await Task.detached { try? await Task.sleep(nanoseconds: 300_000_000) }.value
        }
        return pasteOK
    }

    private func performPaste() async -> Bool {
        if await simulatePaste() { return true }
        guard !Task.isCancelled else { return false }
        Log.info("[TextInserter] CGEvent failed, trying AppleScript")
        return pasteViaAppleScript()
    }

    /// Place text on the clipboard so the user can manually Cmd+V.
    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
