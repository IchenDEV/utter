import Foundation

extension TranscriptFidelityGuard {
    private static let namedIdentifier = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])[A-Z][A-Za-z][A-Za-z0-9_]*(?![A-Za-z0-9_])"#
    )

    static func numberBindingsAreFaithful(source: String, candidate: String) -> Bool {
        let sourceBindings = namedNumberBindings(in: source)
        let candidateBindings = namedNumberBindings(in: candidate)
        let sharedNames = Set(sourceBindings.keys).intersection(candidateBindings.keys)
        return sharedNames.allSatisfy { sourceBindings[$0] == candidateBindings[$0] }
    }

    private static func namedNumberBindings(in text: String) -> [String: [String]] {
        let normalized = text.precomposedStringWithCanonicalMapping
        var bindings: [String: [String]] = [:]
        var previousEnd = normalized.startIndex
        var previousClause = normalized.startIndex
        var previousOwners: [String] = []
        let events = numberEvents(in: normalized, protectedTokens: protectedTokens(in: normalized))
            .sorted { $0.range.location < $1.range.location }
        for event in events {
            guard let range = Range(event.range, in: normalized) else { continue }
            // A clause can assign one quantity to several named owners. Preserve
            // all of them rather than choosing the nearest word after reordering.
            let clause = normalized[..<range.lowerBound].lastIndex(where: {
                ",，;；。\n!?！？".contains($0)
            }).map { normalized.index(after: $0) } ?? normalized.startIndex
            let prefix = String(normalized[max(clause, previousEnd)..<range.lowerBound])
            let fullRange = NSRange(prefix.startIndex..., in: prefix)
            var owners = namedIdentifier.matches(in: prefix, range: fullRange).compactMap { match in
                Range(match.range, in: prefix).map { String(prefix[$0]) }
            }
            if owners.isEmpty, clause == previousClause { owners = previousOwners }
            for name in owners {
                bindings[name, default: []] += numberSemanticKeys(for: event, in: normalized)
            }
            previousEnd = range.upperBound
            previousClause = clause
            previousOwners = owners
        }
        return bindings.mapValues(collapsingRepeatedRangeUnits)
    }
}
