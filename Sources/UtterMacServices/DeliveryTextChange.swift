import Foundation

struct DeliveryTextChange {
    let expectedDocument: String
    let insertedRange: NSRange

    init?(document: String, range: NSRange, replacement: String) {
        let length = document.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= length,
              range.length <= length - range.location, Range(range, in: document) != nil else { return nil }
        expectedDocument = (document as NSString).replacingCharacters(in: range, with: replacement)
        insertedRange = NSRange(location: range.location, length: replacement.utf16.count)
    }
}
