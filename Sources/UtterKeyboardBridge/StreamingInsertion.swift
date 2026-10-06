import Foundation

/// One change to the host field: delete this many characters before the cursor, then insert text.
public struct StreamingEdit: Equatable, Sendable {
    public var deleteCount: Int
    public var insert: String
    public var isEmpty: Bool { deleteCount == 0 && insert.isEmpty }
}

/// Keeps what the keyboard has written into a host field in step with a changing draft, and notices when
/// the user has touched the field so the keyboard stops instead of deleting text it did not write.
///
/// The keyboard only ever deletes characters it inserted itself, back from the end of its own span.
public struct StreamingInsertion: Equatable, Sendable {
    public private(set) var written = ""
    public private(set) var isDetached = false
    private var before = ""
    private var after = ""

    /// How much text before the cursor is remembered. Hosts hand the keyboard a bounded context.
    static let contextLimit = 64

    public init() {}

    /// Remember the field around the cursor when streaming starts.
    public mutating func begin(contextBefore: String?, contextAfter: String?) {
        self = StreamingInsertion()
        before = String((contextBefore ?? "").suffix(Self.contextLimit))
        after = contextAfter ?? ""
    }

    /// The edit that turns the written span into `target`. Records `target` as written; the caller applies it.
    public mutating func edit(to target: String) -> StreamingEdit {
        guard !isDetached else { return StreamingEdit(deleteCount: 0, insert: "") }
        let shared = zip(written, target).prefix { $0 == $1 }.count
        let result = StreamingEdit(deleteCount: written.count - shared, insert: String(target.dropFirst(shared)))
        written = target
        return result
    }

    /// True while the field still looks exactly like our span sitting right before the cursor.
    public func isIntact(contextBefore: String?, contextAfter: String?, selectedText: String?) -> Bool {
        guard !isDetached else { return false }
        guard (selectedText ?? "").isEmpty, (contextAfter ?? "") == after else { return false }
        let expected = before + written
        let actual = contextBefore ?? ""
        if actual.count >= expected.count { return actual.hasSuffix(expected) }
        return expected.hasSuffix(actual)
    }

    /// Stop writing for good; whatever is in the field stays.
    public mutating func detach() { isDetached = true }
}
