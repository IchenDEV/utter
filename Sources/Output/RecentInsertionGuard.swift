import Foundation

enum RecentInsertionGuard {
    /// An undo-and-paste replacement is only safe while the caret still sits
    /// immediately after the previously inserted text. Any typing (including
    /// whitespace), caret move, or focus change makes Cmd+Z undo the wrong
    /// thing, so the caller must degrade to copy-to-clipboard instead.
    /// Returns nil when the focused text is unreadable (AX not exposed) —
    /// the caller keeps today's behavior in that case.
    static func isReplacementSafe(textBeforeCaret: String?, inserted: String) -> Bool? {
        guard let textBeforeCaret, !inserted.isEmpty else { return nil }
        return textBeforeCaret.hasSuffix(inserted)
    }
}
