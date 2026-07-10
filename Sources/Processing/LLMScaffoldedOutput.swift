import Foundation

/// Extracts the final answer from output that uses explicit thinking scaffolds:
/// real tags (`<think>`, `<analysis>`, `<final>`) or standalone heading lines
/// ("Analysis:" / "Final:" on their own lines). Inline headings such as a
/// dictated "分析：市场规模很大。" never activate extraction.
enum LLMScaffoldedOutput {
    static func finalText(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let tagged = finalTaggedText(in: trimmed) {
            return tagged
        }
        return finalHeadingText(in: trimmed)
    }
}

private extension LLMScaffoldedOutput {
    static let thinkingMarkers = [
        "analysis", "reasoning", "reason", "thought", "thoughts",
        "thinking", "scratchpad", "inner monologue", "inner_monologue",
        "分析", "思考", "推理", "推論", "理由", "考え", "考察",
        "분석", "생각", "추론", "이유",
    ]
    static let finalMarkers = [
        "final", "final answer", "final output", "answer",
        "最终", "最终答案", "最终文本", "答案", "输出",
        "最終", "最終回答", "最終テキスト", "回答", "出力",
        "최종", "최종 답변", "최종 텍스트", "답변", "출력",
    ]
    static let finalTagPattern = #"<(?:final|final_answer|answer)(?:\s+[^>]*)?>([\s\S]*?)</(?:final|final_answer|answer)>"#
    static let thinkingTagPattern = #"<(?:analysis|think|thinking|thought|reason|reasoning|reflect|reflection|inner_monologue|scratchpad)(?:\s+[^>]*)?>"#

    static func finalTaggedText(in text: String) -> String? {
        guard hasThinkingTag(text) || isWrappedInFinalTag(text) else { return nil }
        guard let match = text.range(of: finalTagPattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        let matched = String(text[match])
        let content = matched.replacingOccurrences(
            of: finalTagPattern,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        return nonEmpty(content)
    }

    static func finalHeadingText(in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var sawThinkingScaffold = hasThinkingTag(text)
        var sawContentBeforeScaffold = false

        for (index, line) in lines.enumerated() {
            if isIgnorableLine(line) { continue }

            if !sawThinkingScaffold {
                if isStandaloneThinkingHeading(line) {
                    sawThinkingScaffold = true
                    continue
                }
                sawContentBeforeScaffold = true
                continue
            }

            guard let remainder = finalHeadingRemainder(in: line),
                  !sawContentBeforeScaffold else {
                continue
            }

            let following = Array(lines.dropFirst(index + 1))
            let section = remainder.isEmpty ? following : [remainder] + following
            return nonEmpty(trimSection(section))
        }

        return nil
    }

    /// ASR transcripts have no line structure, and a formatting model that
    /// echoes dictated notes keeps the heading and its content on one line
    /// ("分析：市场规模很大。"). A thinking heading alone on its own line is
    /// therefore a reliable scaffold signal, while an inline one is content.
    static func isStandaloneThinkingHeading(_ line: String) -> Bool {
        headingRemainder(in: line, markers: thinkingMarkers) == ""
    }

    static func finalHeadingRemainder(in line: String) -> String? {
        headingRemainder(in: line, markers: finalMarkers)
    }

    static func headingRemainder(in line: String, markers: [String]) -> String? {
        let heading = normalizedHeading(line)
        for marker in markers {
            if heading.localizedCaseInsensitiveCompare(marker) == .orderedSame {
                return ""
            }
            for separator in ["：", ":"] {
                let prefix = marker + separator
                if heading.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil {
                    return String(heading.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    static func normalizedHeading(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = value.first, "#*-_` ".contains(first) {
            value.removeFirst()
        }
        while let last = value.last, "*-_` ".contains(last) {
            value.removeLast()
        }
        return value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func trimSection(_ lines: [String]) -> String {
        var trimmed = lines
        while let first = trimmed.first, isIgnorableLine(first) {
            trimmed.removeFirst()
        }
        while let last = trimmed.last, isIgnorableLine(last) {
            trimmed.removeLast()
        }
        return trimmed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isIgnorableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    static func hasThinkingTag(_ text: String) -> Bool {
        text.range(of: thinkingTagPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isWrappedInFinalTag(_ text: String) -> Bool {
        guard let match = text.range(of: finalTagPattern, options: [.regularExpression, .caseInsensitive]) else {
            return false
        }
        return match.lowerBound == text.startIndex && match.upperBound == text.endIndex
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
