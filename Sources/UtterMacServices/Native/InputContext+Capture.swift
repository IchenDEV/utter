import AppKit
import ApplicationServices
import Foundation
import UtterContracts

extension InputContext {
    @MainActor
    package static func capture(
        targetApp: NSRunningApplication?,
        screenContext: String,
        selectedTextOverride: String? = nil,
        outputMode: OutputMode,
        inputLanguage: InputLanguage,
        source: InputSource
    ) -> InputContext {
        let app = targetApp ?? NSWorkspace.shared.frontmostApplication
        let focusedText = focusedTextContext(for: app)
        let selectedText = normalized(selectedTextOverride, limit: maxFocusedContextLength)
            ?? focusedText?.selectedText
        return InputContext(
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            windowTitle: windowTitle(for: app),
            screenContext: screenContext,
            textBeforeSelection: focusedText?.textBeforeSelection,
            selectedText: selectedText,
            textAfterSelection: focusedText?.textAfterSelection,
            outputMode: outputMode,
            inputLanguage: inputLanguage,
            source: source
        )
    }

    @MainActor
    private static func windowTitle(for app: NSRunningApplication?) -> String? {
        guard let app, AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let title = title(from: axApp, attribute: attribute as CFString) {
                return title
            }
        }
        return nil
    }

    private static func title(from app: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, attribute, &value) == .success,
              let window = value,
              CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }

        var titleValue: CFTypeRef?
        let windowElement = window as! AXUIElement
        guard AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue) == .success else {
            return nil
        }
        return normalized(titleValue as? String, limit: maxWindowTitleLength)
    }

    @MainActor
    private static func focusedTextContext(for app: NSRunningApplication?) -> FocusedTextContext? {
        guard let app, AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedElement = focusedValue,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return nil
        }

        let focusedAXElement = focusedElement as! AXUIElement
        guard let valueText = focusedText(from: focusedAXElement) else {
            return focusedSelectionOnly(from: focusedAXElement)
        }

        var range = CFRange(location: 0, length: 0)
        guard let rangeValue = selectedTextRange(from: focusedAXElement),
              AXValueGetValue(rangeValue, .cfRange, &range) else {
            return FocusedTextContext(
                textBeforeSelection: nil,
                selectedText: focusedSelectionText(from: focusedAXElement),
                textAfterSelection: nil
            )
        }

        return focusedTextContext(text: valueText, range: range)
    }

    private static func focusedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func focusedSelectionOnly(from element: AXUIElement) -> FocusedTextContext? {
        guard let selectedText = focusedSelectionText(from: element) else { return nil }
        return FocusedTextContext(
            textBeforeSelection: nil,
            selectedText: selectedText,
            textAfterSelection: nil
        )
    }

    private static func focusedSelectionText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return normalized(value as? String, limit: maxFocusedContextLength)
    }

    private static func selectedTextRange(from element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success else {
            return nil
        }
        guard let rangeValue = value, CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }
        return (rangeValue as! AXValue)
    }

    private static func focusedTextContext(text: String, range: CFRange) -> FocusedTextContext {
        let nsText = text as NSString
        let textLength = nsText.length
        let start = min(max(range.location, 0), textLength)
        let selectionLength = max(range.length, 0)
        let end = min(start + selectionLength, textLength)
        let beforeStart = max(0, start - maxFocusedContextLength)
        let afterEnd = min(textLength, end + maxFocusedContextLength)

        let before = nsText.substring(with: NSRange(location: beforeStart, length: start - beforeStart))
        let selected = nsText.substring(with: NSRange(location: start, length: end - start))
        let after = nsText.substring(with: NSRange(location: end, length: afterEnd - end))

        return FocusedTextContext(
            textBeforeSelection: before,
            selectedText: selected,
            textAfterSelection: after
        )
    }
}

private struct FocusedTextContext {
    let textBeforeSelection: String?
    let selectedText: String?
    let textAfterSelection: String?
}
