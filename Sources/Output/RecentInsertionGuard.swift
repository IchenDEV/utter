import Foundation

enum RecentInsertionGuard {
    static func isReplacementSafe(
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
              let currentText,
              insertedRange.location >= 0,
              insertedRange.length == inserted.utf16.count,
              NSMaxRange(insertedRange) <= currentText.utf16.count else {
            return false
        }
        return (currentText as NSString).substring(with: insertedRange) == inserted
    }
}
