import Foundation

enum ANELMTokenizerValidation {
    static func samplerVocabularySize(
        tokenizer: [String: Any],
        tokenizerConfig: [String: Any],
        modelVocabularySize: Int
    ) -> Int? {
        guard supportedComponents(in: tokenizer),
              let model = tokenizer["model"] as? [String: Any],
              model["type"] as? String == "BPE",
              let vocabulary = model["vocab"] as? [String: Any],
              !vocabulary.isEmpty,
              let merges = model["merges"] as? [Any],
              !merges.isEmpty,
              tokenizerClass(in: tokenizerConfig) == "Qwen2Tokenizer" else {
            return nil
        }

        let vocabularyEntries = vocabulary.compactMapValues { $0 as? Int }
        let addedTokens = tokenizer["added_tokens"] as? [[String: Any]] ?? []
        let addedEntries = addedTokens.reduce(into: [String: Int]()) { result, token in
            if let content = token["content"] as? String, let id = token["id"] as? Int {
                result[content] = id
            }
        }
        guard vocabularyEntries.count == vocabulary.count,
              addedEntries.count == addedTokens.count else {
            return nil
        }

        let allEntries = vocabularyEntries.merging(addedEntries) { _, _ in -1 }
        let ids = Array(allEntries.values)
        guard allEntries.count == vocabularyEntries.count + addedEntries.count,
              Set(ids).count == ids.count,
              ids.allSatisfy({ $0 >= 0 && $0 < modelVocabularySize }),
              let maximumID = ids.max(),
              Set(ids) == Set(0...maximumID),
              byteLevelAlphabet.allSatisfy({ vocabularyEntries[$0] != nil }),
              vocabularyEntries.keys.allSatisfy(byteLevelTokenIsValid),
              merges.allSatisfy({ mergeIsValid($0, vocabulary: vocabularyEntries) }),
              requiredChatTokensAreMapped(tokenizerConfig, addedTokens: addedTokens),
              configuredTokensAreMapped(tokenizerConfig, vocabulary: allEntries) else {
            return nil
        }
        return maximumID + 1
    }

    private static func supportedComponents(in tokenizer: [String: Any]) -> Bool {
        guard let normalizer = tokenizer["normalizer"] as? [String: Any],
              normalizer["type"] as? String == "NFC",
              let preTokenizer = tokenizer["pre_tokenizer"] as? [String: Any],
              preTokenizer["type"] as? String == "Sequence",
              let parts = preTokenizer["pretokenizers"] as? [[String: Any]],
              parts.count == 2,
              parts[0]["type"] as? String == "Split",
              parts[1]["type"] as? String == "ByteLevel",
              let pattern = parts[0]["pattern"] as? [String: Any],
              pattern.values.contains(where: { ($0 as? String)?.isEmpty == false }),
              let postProcessor = tokenizer["post_processor"] as? [String: Any],
              postProcessor["type"] as? String == "ByteLevel",
              let decoder = tokenizer["decoder"] as? [String: Any],
              decoder["type"] as? String == "ByteLevel" else {
            return false
        }
        return true
    }

    private static func tokenizerClass(in config: [String: Any]) -> String? {
        (config["tokenizer_class"] as? String)?.replacingOccurrences(of: "Fast", with: "")
    }

    private static func configuredTokensAreMapped(
        _ config: [String: Any],
        vocabulary: [String: Int]
    ) -> Bool {
        ["unk_token", "bos_token", "eos_token", "pad_token"].allSatisfy { key in
            guard let value = config[key], !(value is NSNull) else { return true }
            let content = value as? String ?? (value as? [String: Any])?["content"] as? String
            return content.flatMap { vocabulary[$0] } != nil
        }
    }

    private static func requiredChatTokensAreMapped(
        _ config: [String: Any],
        addedTokens: [[String: Any]]
    ) -> Bool {
        let specialTokens = Set(addedTokens.compactMap { token -> String? in
            guard token["special"] as? Bool == true else { return nil }
            return token["content"] as? String
        })
        return specialTokens.contains("<|im_start|>")
            && specialTokens.contains("<|im_end|>")
            && configuredTokenContent(config["eos_token"]) == "<|im_end|>"
    }

    private static func configuredTokenContent(_ value: Any?) -> String? {
        value as? String ?? (value as? [String: Any])?["content"] as? String
    }

    private static func mergeIsValid(_ value: Any, vocabulary: [String: Int]) -> Bool {
        let pair: [String]?
        if let array = value as? [String], array.count == 2 {
            pair = array
        } else if let string = value as? String {
            let parts = string.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            pair = parts.count == 2 ? parts : nil
        } else {
            pair = nil
        }
        guard let pair else { return false }
        return vocabulary[pair[0] + pair[1]] != nil
    }

    private static func byteLevelTokenIsValid(_ token: String) -> Bool {
        token.unicodeScalars.allSatisfy { byteLevelScalars.contains($0) }
    }

    private static let byteLevelAlphabet: [String] = {
        var bytes = Array(33...126) + Array(161...172) + Array(174...255)
        var codePoints = bytes
        for byte in 0...255 where !bytes.contains(byte) {
            bytes.append(byte)
            codePoints.append(256 + codePoints.count - 188)
        }
        return codePoints.compactMap(UnicodeScalar.init).map(String.init)
    }()

    private static let byteLevelScalars = Set(byteLevelAlphabet.compactMap { $0.unicodeScalars.first })
}
