import Foundation
import MLX
import Tokenizers

package final class Audio8HotwordTrie {
    private final class Node {
        var children: [Int: Node] = [:]
        var boosts: [Int: Float] = [:]
    }

    private let root = Node()

    package init(tokenizedPhrases: [[Int]]) {
        for phrase in tokenizedPhrases where !phrase.isEmpty {
            var node = root
            for (index, token) in phrase.enumerated() {
                let boost: Float = index == 0 ? 6.0 : 8.0
                if node.children[token] == nil {
                    node.children[token] = Node()
                }
                node.boosts[token] = max(node.boosts[token] ?? 0, boost)
                node = node.children[token]!
            }
        }
    }

    package func candidateBoosts(generatedTokens: [Int]) -> [Int: Float] {
        var active: [ObjectIdentifier: Node] = [ObjectIdentifier(root): root]
        for token in generatedTokens {
            var next: [ObjectIdentifier: Node] = [ObjectIdentifier(root): root]
            for node in active.values {
                if let child = node.children[token] {
                    next[ObjectIdentifier(child)] = child
                }
            }
            active = next
        }
        var result: [Int: Float] = [:]
        for node in active.values {
            for (token, boost) in node.boosts where node.children[token] != nil {
                result[token] = max(result[token] ?? 0, boost)
            }
        }
        return result
    }
}

package enum Audio8HotwordLogits {
    package static func tokenizedPhrases(
        _ phrases: [String],
        tokenizer: any Tokenizers.Tokenizer
    ) -> [[Int]] {
        var seen = Set<[Int]>()
        var result: [[Int]] = []
        for raw in phrases {
            let phrase = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { continue }
            for variant in textVariants(for: phrase) {
                let ids = tokenizer.encode(text: variant, addSpecialTokens: false).filter { id in
                    guard let token = tokenizer.convertIdToToken(id) else { return true }
                    return !isControlToken(token)
                }
                if !ids.isEmpty, seen.insert(ids).inserted {
                    result.append(ids)
                }
            }
        }
        return result
    }

    private static func textVariants(for phrase: String) -> [String] {
        guard containsASCIIAlphanumeric(phrase), !containsCJKKanaOrHangul(phrase) else {
            return [phrase]
        }
        return [phrase, " " + phrase]
    }

    private static func containsASCIIAlphanumeric(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (48...57).contains(scalar.value) || (65...90).contains(scalar.value)
                || (97...122).contains(scalar.value) || scalar.value == 95
        }
    }

    private static func containsCJKKanaOrHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }
    }

    private static func isControlToken(_ token: String) -> Bool {
        if token.hasPrefix("<|"), token.hasSuffix("|>") { return true }
        return token.hasPrefix("<") && token.hasSuffix(">") && !token.dropFirst().dropLast().contains(" ")
    }

    package static func applyBoosts(
        to logits: MLXArray,
        generatedTokens: [Int],
        trie: Audio8HotwordTrie?,
        topK: Int = 50
    ) -> MLXArray {
        guard let trie else { return logits }
        let boosts = trie.candidateBoosts(generatedTokens: generatedTokens)
        guard !boosts.isEmpty else { return logits }

        let values = logits.asType(.float32).asArray(Float.self)
        let topTokens = Set(
            values.enumerated()
                .sorted { $0.element > $1.element }
                .prefix(topK)
                .map(\.offset)
        )
        let selected = boosts
            .filter { topTokens.contains($0.key) && $0.key < values.count }
            .sorted { $0.key < $1.key }
        guard !selected.isEmpty else { return logits.asType(.float32) }

        let adjusted = logits.asType(.float32)
        let tokenArray = MLXArray(selected.map { Int32($0.key) })
        let addition = MLXArray(selected.map(\.value))
        adjusted[tokenArray] = adjusted[tokenArray] + addition
        return adjusted
    }
}
