import UIKit
import UtterKeyboardBridge

@MainActor
final class KeyboardSelectionOutput {
    private(set) var edit: KeyboardSelectionEdit
    private(set) var isWriting = false
    private(set) var wroteThisOperation = false

    init(edit: KeyboardSelectionEdit) { self.edit = edit }

    func invalidate() { edit.invalidate() }

    func apply(proxy: any UITextDocumentProxy, documentID: () -> UUID?) throws -> Bool {
        wroteThisOperation = false
        let candidate = try edit.beginApply(documentID: documentID(), selectedText: proxy.selectedText,
                                             contextBefore: proxy.documentContextBeforeInput, contextAfter: proxy.documentContextAfterInput)
        isWriting = true
        defer { isWriting = false }
        wroteThisOperation = true; proxy.insertText(candidate)
        return edit.confirmApply(documentID: documentID(), selectedText: proxy.selectedText,
                                 contextBefore: proxy.documentContextBeforeInput, contextAfter: proxy.documentContextAfterInput)
    }

    func restore(proxy: any UITextDocumentProxy, documentID: () -> UUID?) throws -> Bool {
        wroteThisOperation = false
        let change = try edit.beginRestore(documentID: documentID(), selectedText: proxy.selectedText,
                                           contextBefore: proxy.documentContextBeforeInput, contextAfter: proxy.documentContextAfterInput)
        isWriting = true
        defer { isWriting = false }
        func stillOwns(_ deleted: Int) -> Bool {
            guard edit.phase == .restoring, edit.target.isValid(at: Date()), documentID() == edit.target.documentID,
                  proxy.selectedText?.isEmpty != false, let before = proxy.documentContextBeforeInput,
                  let after = proxy.documentContextAfterInput else { return false }
            let remaining = String(edit.candidate.dropLast(deleted))
            let expected = edit.target.before + remaining
            guard before.utf8.suffix(expected.utf8.count).elementsEqual(expected.utf8),
                  String(after.prefix(KeyboardSelectionTarget.contextLimit)).utf8.elementsEqual(edit.target.after.utf8) else { return false }
            if deleted < change.deleteCount {
                guard let actualLast = before.last, let ownedLast = remaining.last,
                      String(actualLast).utf8.elementsEqual(String(ownedLast).utf8) else { return false }
                let next = edit.target.before + String(remaining.dropLast())
                let nextBefore = String(before.dropLast())
                return nextBefore.utf8.suffix(next.utf8.count).elementsEqual(next.utf8) &&
                    Array(before + after) == Array(before) + Array(after) &&
                    Array(nextBefore + after) == Array(nextBefore) + Array(after)
            }
            return true
        }
        for deleted in 0..<change.deleteCount {
            guard stillOwns(deleted) else {
                _ = edit.confirmRestore(documentID: documentID(), selectedText: proxy.selectedText,
                                        contextBefore: proxy.documentContextBeforeInput, contextAfter: proxy.documentContextAfterInput)
                return false
            }
            wroteThisOperation = true; proxy.deleteBackward()
        }
        guard stillOwns(change.deleteCount) else {
            _ = edit.confirmRestore(documentID: documentID(), selectedText: proxy.selectedText,
                                    contextBefore: proxy.documentContextBeforeInput, contextAfter: proxy.documentContextAfterInput)
            return false
        }
        if !change.insert.isEmpty { wroteThisOperation = true; proxy.insertText(change.insert) }
        return edit.confirmRestore(documentID: documentID(), selectedText: proxy.selectedText,
                                   contextBefore: proxy.documentContextBeforeInput, contextAfter: proxy.documentContextAfterInput)
    }
}
