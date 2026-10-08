import Foundation

extension TranscriptFidelityGuard {
    static func protectedFactCounts(in text: String) -> [String: Int] {
        let normalized = text.precomposedStringWithCanonicalMapping
        let tokens = protectedTokens(in: normalized)
        var facts = tokens.filter { $0.category != "number" }.map(\.key)
        for event in numberEvents(in: normalized, protectedTokens: tokens) {
            var pending: [String] = []
            var recentFacts: [Int] = []
            for key in numberSemanticKeys(for: event, in: normalized) {
                if key.hasPrefix("number:") {
                    pending.append(key)
                } else if key.hasPrefix("unit:") {
                    recentFacts = pending.map { value in
                        facts.append(value + "|" + key)
                        return facts.count - 1
                    }
                    pending.removeAll()
                } else if key.hasPrefix("period:") {
                    for index in recentFacts { facts[index] += "|" + key }
                }
            }
            facts += pending
        }
        return Dictionary(facts.map { ($0, 1) }, uniquingKeysWith: +)
    }
}
