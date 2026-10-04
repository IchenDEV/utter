import Foundation

struct DeliveryTextChange {
    let expectedDocument: String
    let insertedRange: NSRange

    init?(document: String, range: NSRange, replacement: String) {
        let length = document.utf16.count
        let value = document as NSString
        guard range.location >= 0, range.length >= 0, range.location <= length,
              range.length <= length - range.location,
              Self.isScalarBoundary(range.location, in: value),
              Self.isScalarBoundary(range.location + range.length, in: value) else { return nil }
        expectedDocument = value.replacingCharacters(in: range, with: replacement)
        insertedRange = NSRange(location: range.location, length: replacement.utf16.count)
    }

    private static func isScalarBoundary(_ offset: Int, in value: NSString) -> Bool {
        offset == value.length || !(0xDC00...0xDFFF).contains(value.character(at: offset))
    }
}
