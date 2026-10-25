import Foundation

/// Chromium (Electron apps and Chromium browser pages) accepts an Accessibility selected-text write
/// and reports success without changing the page. Its nodes carry this attribute; no app is named.
/// `AXDOMClassList` is not used: WebKit exposes it too and its behavior is unmeasured.
enum WebContentEditorSignature {
    static let attribute = "ChromeAXNodeId"

    static func matches(attributeNames: [String]) -> Bool {
        attributeNames.contains(attribute)
    }
}
