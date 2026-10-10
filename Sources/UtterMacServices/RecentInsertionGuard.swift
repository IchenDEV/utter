import Foundation

package enum RecentInsertionGuard {
    package static func isReplacementSafe(
        sameTarget: Bool,
        currentSelection: NSRange?,
        insertedRange: NSRange,
        currentText: String?,
        inserted: String
    ) -> Bool {
        guard sameTarget,
              !inserted.isEmpty,
              let currentSelection,
              currentSelection.length == 0,
              currentSelection.location == NSMaxRange(insertedRange),
              insertedRange.length == inserted.utf16.count,
              let currentText,
              insertedRange.location >= 0,
              NSMaxRange(insertedRange) <= currentText.utf16.count else {
            return false
        }
        return (currentText as NSString).substring(with: insertedRange) == inserted
    }
}

