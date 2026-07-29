import Foundation

enum TranscriptionSanitizer {
    static func normalizeInput(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "[ ]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func prepare(_ text: String, audioActivity: AudioCaptureActivity? = nil) -> String? {
        let normalized = normalizeTranscript(text)
        guard !isNonSpeechArtifact(normalized) else { return nil }

        // Whole-transcript repetition is a hallucination pattern that shows up
        // when the model has little real speech to work with. Deliberate spoken
        // repetition ("这个方案可以这个方案可以") is normal emphasis, so only
        // collapse when the audio itself suggests hallucination.
        let collapsed: String
        if audioActivity?.hasWeakSpeechEvidence == true {
            collapsed = collapseRepeatedTranscript(normalized)
        } else {
            collapsed = normalized
        }
        guard !isNonSpeechArtifact(collapsed) else { return nil }

        guard let dehallucinated = removeWeakAudioHallucination(
            from: collapsed,
            audioActivity: audioActivity
        ) else {
            return nil
        }

        return dehallucinated
    }

    static func previewText(_ text: String, inputLanguage: InputLanguage = .auto) -> String {
        let normalized = normalizeInput(normalizeTranscript(text))
        return isNonSpeechArtifact(normalized) ? "" : normalized
    }

    static func isNonSpeechArtifact(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if explicitNoSpeechArtifacts.contains(trimmed.lowercased()) { return true }

        let meaningfulScalars = trimmed.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }
        if meaningfulScalars.isEmpty { return true }

        let cleaned = normalizedPhrase(trimmed)
        return cleaned.isEmpty || noSpeechArtifacts.contains(cleaned)
    }

    static func collapseRepeatedTranscript(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(normalized)
        guard characters.count >= 12 else { return normalized }

        var bestMatch: String?
        for splitIndex in 1..<characters.count {
            let first = String(characters[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let second = String(characters[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRepeatCandidate(first) else { continue }
            if canonicalText(first) == canonicalText(second) {
                bestMatch = first
            } else if repeatsCoverWholeTranscript(unit: first, fullText: normalized) {
                bestMatch = first
            }
        }

        return bestMatch ?? normalized
    }

    private static func isRepeatCandidate(_ text: String) -> Bool {
        let canonical = canonicalText(text)
        guard canonical.count >= 6 else { return false }

        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return wordCount >= 2 || containsCJK(text)
    }

    private static func normalizeTranscript(_ text: String) -> String {
        normalizeInput(text)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(
                of: #"<\|(?:nospeech|no_speech|notimestamps|startoftranscript|endoftext)\|>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeWeakAudioHallucination(
        from text: String,
        audioActivity: AudioCaptureActivity?
    ) -> String? {
        guard audioActivity?.hasWeakSpeechEvidence == true else { return text }
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in trailingHallucinationPatterns {
            let candidate = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                cleaned = candidate
            }
        }
        return isNonSpeechArtifact(cleaned) ? nil : cleaned
    }

    private static func normalizedPhrase(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }))
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    }

    private static func canonicalText(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || isCJKScalar(scalar)
        }))
        .lowercased()
    }

    private static func repeatsCoverWholeTranscript(unit: String, fullText: String) -> Bool {
        let unitCanonical = canonicalText(unit)
        guard unitCanonical.count >= 6 else { return false }

        var remainder = canonicalText(fullText)
        var repeatCount = 0
        while remainder.hasPrefix(unitCanonical) {
            remainder.removeFirst(unitCanonical.count)
            repeatCount += 1
        }
        return repeatCount >= 2 && remainder.isEmpty
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isCJKScalar)
    }

    private static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(Int(scalar.value))
            || (0x3400...0x4DBF).contains(Int(scalar.value))
    }

    private static let noSpeechArtifacts: Set<String> = [
        "blankaudio",
        "nospeech",
    ]

    private static let explicitNoSpeechArtifacts: Set<String> = [
        "(无)", "（无）", "[无]", "【无】",
        "(無)", "（無）", "[無]", "【無】",
        "(silence)", "[silence]", "<silence>",
        "(silent)", "[silent]", "<silent>",
        "(blank audio)", "[blank audio]", "<blank audio>",
        "(no speech)", "[no speech]", "<no speech>",
        "[blank_audio]", "<blank_audio>",
    ]

    private static let trailingHallucinationPatterns = [
        #"\s*(?:thank you for watching|thanks for watching)[.!?。！？]*\s*$"#,
        #"\s*(?:感谢观看|謝謝觀看|谢谢观看|谢谢收看|感謝收看)[。.!！!？?]*\s*$"#,
        #"\s*字幕由\s*[^。.!！!？?\n]{0,40}(?:提供|制作|製作)[。.!！!？?]*\s*$"#,
        #"\s*subtitles?\s+(?:by|provided by)\s+[^\n]{0,60}[.!?。！？]*\s*$"#,
    ]
}
