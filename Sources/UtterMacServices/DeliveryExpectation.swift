import Foundation

/// Expected field value after a delivery. A wrong expectation can only end `uncertain`; it never causes another write.
enum DeliveryExpectation {
    /// A Chromium rich-text editor reports an empty paragraph as one line feed, and drops it once text is inserted.
    private static let emptyParagraph = "\n"

    static func expectedDocument(document: String, range: NSRange, replacement: String,
                                 isWebContentEditor: Bool) -> String? {
        guard let change = DeliveryTextChange(document: document, range: range, replacement: replacement) else { return nil }
        // Only the measured shape: caret at the start of a lone placeholder, and text being inserted (not a delete).
        guard isWebContentEditor, document == emptyParagraph, range == NSRange(location: 0, length: 0),
              !replacement.isEmpty else { return change.expectedDocument }
        return replacement
    }
}
