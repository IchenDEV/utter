import Foundation
import UtterKeyboardBridge

@MainActor protocol UITextDocumentProxy {
    var selectedText: String? { get }
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    func insertText(_ text: String)
    func deleteBackward()
}

@MainActor final class Proxy: UITextDocumentProxy {
    var id = UUID()
    var before = "前文 "
    var after = " 后文"
    var selection: String? = "你好👨‍👩‍👧‍👦"
    var hideBefore = false
    var inserts = 0
    var deletes = 0
    var onInsert: (() -> Void)?
    var onDelete: (() -> Void)?
    var selectedText: String? { selection }
    var documentContextBeforeInput: String? { hideBefore ? nil : before }
    var documentContextAfterInput: String? { after }
    func insertText(_ text: String) { inserts += 1; selection = nil; before += text; onInsert?() }
    func deleteBackward() { deletes += 1; if !before.isEmpty { before.removeLast() }; onDelete?() }
}

@main struct ProxyCheck {
    @MainActor static func main() throws {
        var observations: [[String: Any]] = []
        func check(_ name: String, _ value: Bool) { observations.append(["case": name, "passed": value]) }
        func fixture() throws -> (Proxy, KeyboardSelectionOutput) {
            let proxy = Proxy()
            let target = try KeyboardSelectionTarget(documentID: proxy.id, selectedText: proxy.selection,
                                                      contextBefore: proxy.before, contextAfter: proxy.after)
            let edit = try KeyboardSelectionEdit(id: UUID(), target: target, candidate: "您好👨‍👩‍👧‍👦")
            return (proxy, KeyboardSelectionOutput(edit: edit))
        }
        do {
            let (proxy, writer) = try fixture()
            let applied = try writer.apply(proxy: proxy, documentID: { proxy.id })
            check("replace-selection-in-one-insert", applied && proxy.inserts == 1 && proxy.deletes == 0 && proxy.before == "前文 您好👨‍👩‍👧‍👦")
            let restored = try writer.restore(proxy: proxy, documentID: { proxy.id })
            check("restore-exact-original-once", restored && proxy.deletes == 3 && proxy.before == "前文 你好👨‍👩‍👧‍👦" && proxy.after == " 后文")
            _ = try? writer.restore(proxy: proxy, documentID: { proxy.id })
            check("repeated-restore-no-effect", proxy.inserts == 2 && proxy.deletes == 3)
        }
        do {
            for (before, candidate) in [("a", "\u{301}"), ("🇦", "🇧🇨"), ("\r", "\n")] {
                let proxy = Proxy(); proxy.before = before; proxy.selection = "x"; proxy.after = ""
                let target = try KeyboardSelectionTarget(documentID: proxy.id, selectedText: "x", contextBefore: before, contextAfter: "")
                var refused = false
                do { _ = try KeyboardSelectionEdit(id: UUID(), target: target, candidate: candidate) } catch { refused = true }
                check("grapheme-edge-refused-before-effect-\(before)", refused && proxy.before == before && proxy.selection == "x" && proxy.inserts == 0 && proxy.deletes == 0)
            }
        }
        do {
            let proxy = Proxy(); proxy.before = ""; proxy.selection = "x"; proxy.after = "🇧"
            let target = try KeyboardSelectionTarget(documentID: proxy.id, selectedText: "x", contextBefore: "", contextAfter: "🇧")
            let writer = KeyboardSelectionOutput(edit: try KeyboardSelectionEdit(id: UUID(), target: target, candidate: "🇦 "))
            _ = try writer.apply(proxy: proxy, documentID: { proxy.id })
            let restored = try writer.restore(proxy: proxy, documentID: { proxy.id })
            check("prospective-grapheme-join-refuses-delete-before-effect", !restored && !writer.wroteThisOperation && proxy.deletes == 0 && proxy.before == "🇦 " && proxy.after == "🇧")
        }
        do {
            let (proxy, writer) = try fixture(); proxy.id = UUID()
            _ = try? writer.apply(proxy: proxy, documentID: { proxy.id })
            check("changed-document-no-effect", proxy.inserts == 0 && proxy.deletes == 0 && proxy.selection == "你好👨‍👩‍👧‍👦")
        }
        do {
            let (proxy, writer) = try fixture(); proxy.selection = "别的选区"
            _ = try? writer.apply(proxy: proxy, documentID: { proxy.id })
            check("changed-selection-no-effect", proxy.inserts == 0 && proxy.selection == "别的选区")
        }
        do {
            let (proxy, writer) = try fixture(); proxy.onInsert = { proxy.hideBefore = true }
            let applied = try writer.apply(proxy: proxy, documentID: { proxy.id })
            proxy.hideBefore = false; _ = try? writer.restore(proxy: proxy, documentID: { proxy.id })
            check("unavailable-readback-uncertain-no-retry", !applied && writer.edit.phase == .uncertain && proxy.inserts == 1 && proxy.deletes == 0)
        }
        do {
            let (proxy, writer) = try fixture(); _ = try writer.apply(proxy: proxy, documentID: { proxy.id })
            proxy.onDelete = { proxy.id = UUID() }
            let restored = try writer.restore(proxy: proxy, documentID: { proxy.id })
            check("document-change-mid-restore-stops-before-next-delete", !restored && proxy.deletes == 1 && proxy.inserts == 1 && writer.edit.phase == .uncertain)
        }
        do {
            let (proxy, writer) = try fixture(); _ = try writer.apply(proxy: proxy, documentID: { proxy.id })
            proxy.onDelete = { proxy.before += "别人输入" }
            let restored = try writer.restore(proxy: proxy, documentID: { proxy.id })
            check("later-input-mid-restore-is-not-deleted", !restored && proxy.deletes == 1 && proxy.before.hasSuffix("别人输入") && proxy.inserts == 1)
        }
        do {
            let (proxy, writer) = try fixture(); _ = try writer.apply(proxy: proxy, documentID: { proxy.id })
            proxy.before += "后加字"; _ = try? writer.restore(proxy: proxy, documentID: { proxy.id })
            check("later-input-preserved", proxy.before == "前文 您好👨‍👩‍👧‍👦后加字" && proxy.deletes == 0)
        }
        do {
            let (proxy, writer) = try fixture(); writer.invalidate()
            _ = try? writer.apply(proxy: proxy, documentID: { proxy.id })
            check("cancel-before-apply-no-effect", proxy.inserts == 0 && proxy.deletes == 0)
        }
        do {
            let (proxy, writer) = try fixture(); proxy.onInsert = { proxy.id = UUID() }
            let applied = try writer.apply(proxy: proxy, documentID: { proxy.id })
            _ = try? writer.restore(proxy: proxy, documentID: { proxy.id })
            check("document-rechecked-after-native-effect", !applied && proxy.inserts == 1 && proxy.deletes == 0)
        }
        do {
            let (proxy, writer) = try fixture(); _ = try writer.apply(proxy: proxy, documentID: { proxy.id })
            proxy.onDelete = { writer.invalidate() }
            let restored = try writer.restore(proxy: proxy, documentID: { proxy.id })
            _ = try? writer.restore(proxy: proxy, documentID: { proxy.id })
            check("invalidation-stops-restore-after-owned-partial-effect", !restored && proxy.deletes == 1 && proxy.inserts == 1)
        }
        let failures = observations.filter { $0["passed"] as? Bool != true }.count
        let report: [String: Any] = ["scope": "Actual native writer source and bridge types; UITextDocumentProxy and field behavior are stubs",
                                   "deviceCommandsExecuted": false, "nativeUIKitAcceptance": "unverified", "observations": observations, "failures": failures]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]))
        if failures != 0 { exit(1) }
    }
}
