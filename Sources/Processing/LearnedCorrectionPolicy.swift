import Foundation

enum LearnedCorrectionPolicy {
    private static let isolatedFillers: Set<String> = [
        "嗯", "呃", "额", "唔", "啊", "哦", "um", "uh", "hmm", "hm"
    ]

    static func isUnsafeSource(_ text: String) -> Bool {
        let lexical = String(text.lowercased().filter { $0.isLetter || $0.isNumber })
        return isolatedFillers.contains(lexical)
            || TranscriptionSanitizer.isNonSpeechArtifact(text)
    }
}

extension DictionaryEntry {
    func applies(bundleIdentifier: String?, languageCode: String?) -> Bool {
        guard isEffective else { return false }
        if origin == .learned {
            guard !LearnedCorrectionPolicy.isUnsafeSource(original),
                  !appScopes.isEmpty || (self.languageCode != nil
                      && self.languageCode != InputLanguage.auto.rawValue) else { return false }
        }
        if !appScopes.isEmpty {
            guard let bundleIdentifier,
                  appScopes.contains(where: { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }) else {
                return false
            }
        }
        if let expected = self.languageCode, expected != InputLanguage.auto.rawValue {
            guard let languageCode,
                  expected.split(separator: "-").first?.lowercased()
                    == languageCode.split(separator: "-").first?.lowercased() else {
                return false
            }
        }
        return true
    }
}
