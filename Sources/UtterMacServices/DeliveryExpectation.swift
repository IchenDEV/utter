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

    /// Every value the field may hold once the text has landed. A caret at the very start of an empty-looking web
    /// editor is the one case with two: some editors (ChatGPT) keep a placeholder inside the value and drop it on
    /// insert, so the field ends up equal to the replacement alone. Seeing exactly the replacement can only mean the
    /// text arrived, so it is accepted in addition to the normal computation. Values equal to `document` are
    /// never returned: an unchanged field proves nothing.
    static func acceptedDocuments(document: String, range: NSRange, replacement: String,
                                  isWebContentEditor: Bool) -> [String]? {
        guard let primary = expectedDocument(document: document, range: range, replacement: replacement,
                                             isWebContentEditor: isWebContentEditor) else { return nil }
        var accepted = [primary]
        if isWebContentEditor, range == NSRange(location: 0, length: 0), !replacement.isEmpty,
           replacement != primary { accepted.append(replacement) }
        return accepted.filter { $0 != document }
    }
}
