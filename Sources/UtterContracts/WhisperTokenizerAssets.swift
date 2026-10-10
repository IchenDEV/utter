import Foundation

package struct WhisperTokenizerAssets: Sendable {
    package static let directoryName = "utter-tokenizer"
    package static let manifestName = "utter-tokenizer.json"
    package let directory: URL
    package let repository: String
    package let vocabularySize: Int

    package static func repository(for model: String) -> String? {
        let variant = WhisperModelSelection.canonicalVariant(model)
        switch variant {
        case "tiny", "tiny.en", "base", "base.en", "small", "small.en", "medium", "medium.en", "large-v2", "large-v3":
            return "openai/whisper-" + variant
        case "large", "large-v1": return "openai/whisper-large"
        case "large-v3-turbo": return "openai/whisper-large-v3"
        default: return nil
        }
    }

    package static func read(at model: URL, expectedModel: String? = nil) throws -> Self {
        let nested = model.appendingPathComponent(directoryName, isDirectory: true)
        let directory = FileManager.default.fileExists(atPath: nested.path) ? nested : model
        let config = try object(directory.appendingPathComponent("tokenizer_config.json"))
        let data = try object(directory.appendingPathComponent("tokenizer.json"))
        let manifestURL = directory.appendingPathComponent(manifestName)
        let manifest = FileManager.default.fileExists(atPath: manifestURL.path) ? try object(manifestURL) : [:]
        guard let repository = manifest["repository"] as? String ?? config["_name_or_path"] as? String,
              repository.hasPrefix("openai/whisper-"), Self.repository(for: repository) == repository,
              (config["tokenizer_class"] as? String)?.hasPrefix("WhisperTokenizer") == true,
              let modelData = data["model"] as? [String: Any], modelData["type"] as? String == "BPE",
              let vocabulary = modelData["vocab"] as? [String: Int], !vocabulary.isEmpty,
              let merges = modelData["merges"] as? [Any], !merges.isEmpty,
              let added = data["added_tokens"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        if let expected = Self.repository(for: expectedModel ?? model.lastPathComponent), expected != repository {
            throw CocoaError(.fileReadCorruptFile)
        }
        var tokens = vocabulary
        for token in added {
            guard let text = token["content"] as? String, let id = token["id"] as? Int,
                  tokens[text] == nil || tokens[text] == id else { throw CocoaError(.fileReadCorruptFile) }
            tokens[text] = id
        }
        let size = repository.hasSuffix(".en") ? 51864 : repository.hasSuffix("large-v3") ? 51866 : 51865
        let ids = Set(tokens.values)
        guard ids.count == size, ids.min() == 0, ids.max() == size - 1 else { throw CocoaError(.fileReadCorruptFile) }
        let end = repository.hasSuffix(".en") ? 50256 : 50257
        guard tokens["<|endoftext|>"] == end, tokens["<|startoftranscript|>"] == end + 1,
              ["<|en|>", "<|transcribe|>", "<|translate|>", "<|startofprev|>", "<|notimestamps|>", "<|0.00|>", "<|30.00|>"].allSatisfy({ tokens[$0] != nil }),
              tokens["<|nospeech|>"] != nil || tokens["<|nocaptions|>"] != nil,
              repository.hasSuffix(".en") || tokens["<|zh|>"] != nil else { throw CocoaError(.fileReadCorruptFile) }
        return Self(directory: directory, repository: repository, vocabularySize: size)
    }

    package static func writeManifest(repository: String, at directory: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "repository": repository], options: [.sortedKeys])
        try data.write(to: directory.appendingPathComponent(manifestName), options: .atomic)
    }

    private static func object(_ url: URL) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }
}
