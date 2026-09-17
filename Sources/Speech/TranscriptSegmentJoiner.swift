import Foundation

/// Joins the per-chunk texts WhisperKit returns when VAD chunking splits a
/// recording. Latin scripts need a separating space; CJK scripts must not get
/// one. When the language is auto-detected (`nil`), fall back to inspecting the
/// boundary characters so CJK output still joins without spaces.
enum TranscriptSegmentJoiner {
    static func joined(_ segments: [String], language: String?) -> String {
        let cleaned = segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard var result = cleaned.first else { return "" }

        for segment in cleaned.dropFirst() {
            result += separator(previous: result, next: segment, language: language)
            result += segment
        }
        return result
    }

    static func separator(previous: String, next: String, language: String?) -> String {
        if let language, !language.isEmpty {
            return usesNoSpaceScript(language) ? "" : " "
        }
        if let last = previous.last, let first = next.first,
           isNoSpaceBoundary(last) || isNoSpaceBoundary(first) {
            return ""
        }
        return " "
    }

    private static func usesNoSpaceScript(_ language: String) -> Bool {
        ["zh", "yue", "ja", "ko"].contains(language.lowercased())
    }

    private static func isNoSpaceBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.contains(where: NoSpaceScript.contains)
    }
}
