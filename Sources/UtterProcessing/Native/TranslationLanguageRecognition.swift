import Foundation
import NaturalLanguage
import UtterContracts

package enum TranslationLanguageRecognition {
    package static func assess(_ text: String, target: TranslationLanguage,
                               knownTerms: [String] = []) -> TranslationAssessment {
        let sample = removingNames(TranslationLanguageSample.prepare(text, knownTerms: knownTerms))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let scores = Dictionary(uniqueKeysWithValues: recognizer.languageHypotheses(withMaximum: 16)
            .map { ($0.key.rawValue, $0.value) })
        return .assess(target: target,
            hasLinguisticContent: TranslationLanguageSample.hasLinguisticContent(sample), scores: scores)
    }

    private static func removingNames(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var ranges: [NSRange] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                ranges.append(NSRange(range, in: text))
            }
            return true
        }
        let sample = NSMutableString(string: text)
        for range in ranges { sample.replaceCharacters(in: range, with: String(repeating: " ", count: range.length)) }
        return sample as String
    }
}
