import Foundation

@MainActor
package final class ContributionRegistry<Value> {
    private struct Entry {
        let token: UUID
        let value: Value
    }
    private var entries: [String: Entry] = [:]

    package init() {}

    package var ids: [String] { entries.keys.sorted() }

    package func value(for id: String) -> Value? { entries[id]?.value }

    package func contribute(_ id: String, value: Value, scope: PluginScope) throws {
        guard entries[id] == nil else { throw PluginRuntimeError.duplicateService(id) }
        let token = UUID()
        try scope.onDispose { [self] in
            if entries[id]?.token == token { entries.removeValue(forKey: id) }
        }
        entries[id] = Entry(token: token, value: value)
    }
}
