import Foundation

struct CorrectionCaptureRegionLocator: Equatable, Sendable {
    private static let anchorLength = 48
    let originalRange: NSRange
    let baselineDocumentLength: Int
    let trailingDocumentLength: Int
    let prefixAnchor: String
    let suffixAnchor: String

    init?(documentText: String, insertedRange: NSRange) {
        let document = documentText as NSString
        guard insertedRange.location >= 0,
              insertedRange.length > 0,
              NSMaxRange(insertedRange) <= document.length else {
            return nil
        }
        originalRange = insertedRange
        baselineDocumentLength = document.length
        trailingDocumentLength = document.length - NSMaxRange(insertedRange)

        let prefixLength = min(Self.anchorLength, insertedRange.location)
        prefixAnchor = document.substring(with: NSRange(
            location: insertedRange.location - prefixLength,
            length: prefixLength
        ))
        let suffixLength = min(Self.anchorLength, trailingDocumentLength)
        suffixAnchor = document.substring(with: NSRange(
            location: NSMaxRange(insertedRange),
            length: suffixLength
        ))
    }

    func editedText(in currentText: String) -> String? {
        let current = currentText as NSString
        let start: Int
        if prefixAnchor.isEmpty {
            start = originalRange.location
        } else {
            let expected = max(0, originalRange.location - prefixAnchor.utf16.count)
            guard let prefixRange = nearbyRange(
                of: prefixAnchor,
                in: current,
                expectedLocation: expected,
                searchRadius: 192
            ) else { return nil }
            start = NSMaxRange(prefixRange)
        }

        let end: Int
        if suffixAnchor.isEmpty {
            end = current.length - trailingDocumentLength
        } else {
            let expected = max(start, NSMaxRange(originalRange) + current.length - baselineDocumentLength)
            guard let suffixRange = nearbyRange(
                of: suffixAnchor,
                in: current,
                expectedLocation: expected,
                searchRadius: max(512, originalRange.length * 2)
            ) else { return nil }
            end = suffixRange.location
        }

        let length = end - start
        guard start >= 0,
              length >= 0,
              end <= current.length,
              length <= max(1_024, originalRange.length * 4 + 256) else {
            return nil
        }
        return current.substring(with: NSRange(location: start, length: length))
    }
}
private extension CorrectionCaptureRegionLocator {
    func nearbyRange(
        of needle: String,
        in text: NSString,
        expectedLocation: Int,
        searchRadius: Int
    ) -> NSRange? {
        let lower = max(0, expectedLocation - searchRadius)
        let upper = min(text.length, expectedLocation + needle.utf16.count + searchRadius)
        guard upper >= lower else { return nil }
        let match = text.range(
            of: needle,
            options: [],
            range: NSRange(location: lower, length: upper - lower)
        )
        return match.location == NSNotFound ? nil : match
    }
}
