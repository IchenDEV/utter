import Foundation
import NaturalLanguage
import WhisperKit
import UtterContracts

struct LocalWhisperTokenizer: WhisperTokenizer {
    private let tokenizer: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>

    static func load(_ assets: WhisperTokenizerAssets) async throws -> Self {
        try Task.checkCancellation()
        let tokenizer = try await AutoTokenizerWrapper.from(modelFolder: assets.directory)
        try Task.checkCancellation()
        return try Self(tokenizer)
    }

    init(_ tokenizer: TokenizerWrapper) throws {
        func token(_ text: String) throws -> Int {
            guard let id = tokenizer.convertTokenToId(text) else { throw CocoaError(.fileReadCorruptFile) }
            return id
        }
        guard let whitespace = tokenizer.encode(text: " ", addSpecialTokens: false).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let end = try token("<|endoftext|>")
        guard let noSpeech = tokenizer.convertTokenToId("<|nospeech|>") ?? tokenizer.convertTokenToId("<|nocaptions|>") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.tokenizer = tokenizer
        specialTokens = try SpecialTokens(endToken: end, englishToken: token("<|en|>"),
            noSpeechToken: noSpeech, noTimestampsToken: token("<|notimestamps|>"),
            specialTokenBegin: end, startOfPreviousToken: token("<|startofprev|>"),
            startOfTranscriptToken: token("<|startoftranscript|>"), timeTokenBegin: token("<|0.00|>"),
            transcribeToken: token("<|transcribe|>"), translateToken: token("<|translate|>"), whitespaceToken: whitespace)
        allLanguageTokens = Set(Constants.languages.values.compactMap { tokenizer.convertTokenToId("<|\($0)|>") })
    }

    func encode(text: String) -> [Int] { tokenizer.encode(text: text) }
    func decode(tokens: [Int]) -> String { tokenizer.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { tokenizer.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { tokenizer.convertIdToToken(id) }

    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(decode(tokens: tokenIds.filter { $0 < specialTokens.specialTokenBegin }))
        let separatesWithoutSpaces = ["zh", "ja", "th", "lo", "my", "yue"].contains(recognizer.dominantLanguage?.rawValue ?? "")
        var words: [String] = [], groups: [[Int]] = [], pending: [Int] = []
        for (index, token) in tokenIds.enumerated() {
            pending.append(token)
            let text = decode(tokens: pending)
            // A BPE token may contain only part of a UTF-8 character.
            guard !text.contains("\u{fffd}") || index == tokenIds.count - 1 else { continue }
            let punctuation = !text.isEmpty && text.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
            if words.isEmpty || separatesWithoutSpaces || text.hasPrefix(" ") || punctuation || pending[0] >= specialTokens.specialTokenBegin {
                words.append(text); groups.append(pending)
            } else {
                words[words.count - 1] += text
                groups[groups.count - 1].append(contentsOf: pending)
            }
            pending.removeAll(keepingCapacity: true)
        }
        return (words, groups)
    }
}

final class OfflineWhisperKit: WhisperKit {
    var installedTokenizer: WhisperTokenizerAssets?

    override func loadTokenizerIfNeeded() async throws {
        try Task.checkCancellation()
        guard let assets = installedTokenizer, tokenizer != nil,
              let logits = textDecoder.logitsSize, let encoder = audioEncoder.embedSize,
              logits == assets.vocabularySize,
              WhisperModelDimensions.supports(repository: assets.repository, logits: logits, encoder: encoder) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        textDecoder.isModelMultilingual = logits != 51864
    }
}
