import AppKit
import ApplicationServices
import Foundation

@MainActor
struct AXTargetState {
    let processIdentifier: Int32
    let element: AXUIElement
    let selection: NSRange
    let before: String
    let selected: String
    let after: String

    static func capture() -> AXTargetState? {
        guard let (processIdentifier, element) = focusedIdentity() else { return nil }
        guard let selection = range(of: element), let text = value(of: element) else { return nil }
        let document = text as NSString
        guard selection.location >= 0, selection.length >= 0, NSMaxRange(selection) <= document.length else { return nil }
        let start = max(0, selection.location - 500)
        let end = min(document.length, NSMaxRange(selection) + 500)
        return AXTargetState(processIdentifier: processIdentifier, element: element, selection: selection,
            before: document.substring(with: NSRange(location: start, length: selection.location - start)),
            selected: document.substring(with: selection),
            after: document.substring(with: NSRange(location: NSMaxRange(selection), length: end - NSMaxRange(selection)))
        )
    }

    static func focusedIdentity() -> (Int32, AXUIElement)? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
            kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (app.processIdentifier, focused as! AXUIElement)
    }

    func matches(_ other: AXTargetState, selection expectedSelection: NSRange? = nil) -> Bool {
        processIdentifier == other.processIdentifier && CFEqual(element, other.element)
            && other.selection == (expectedSelection ?? selection)
            && (expectedSelection != nil || (before == other.before && selected == other.selected && after == other.after))
    }

    func restoreSelection() {
        guard let current = Self.capture(), processIdentifier == current.processIdentifier,
              CFEqual(element, current.element) else { return }
        _ = Self.setRange(selection, of: element)
    }

    static func setRange(_ range: NSRange, of element: AXUIElement) -> Bool {
        var value = CFRange(location: range.location, length: range.length)
        guard let encoded = AXValueCreate(.cfRange, &value) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, encoded) == .success
    }

    static func range(of element: AXUIElement) -> NSRange? {
        var encoded: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &encoded) == .success,
              let encoded, CFGetTypeID(encoded) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(encoded as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func value(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
