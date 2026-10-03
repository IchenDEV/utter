import Foundation
import UtterContracts

extension FormattedOutputCleaner {
    static func finalTextHeadingRemainder(in line: String) -> String? {
        headingRemainder(
            in: line,
            markers: finalTextMarkers
        )
    }

    static func isExplanationHeading(_ line: String) -> Bool {
        headingRemainder(
            in: line,
            markers: explanationMarkers
        ) != nil
    }

    static var finalTextMarkers: [String] {
        [
            "整理后文本", "整理后", "最终文本", "润色后", "输出结果",
            "Final text", "Rewritten text", "Output",
            "最終テキスト", "出力", "書き換え後", "修正後",
            "최종 텍스트", "출력", "수정된 텍스트", "정리된 텍스트",
        ]
    }

    static var explanationMarkers: [String] {
        [
            "说明", "解释", "处理说明", "纠错说明", "纠错与同音词修正",
            "Reasoning", "Explanation", "Notes",
            "説明", "理由", "注釈", "補足", "解説",
            "설명", "이유", "비고", "메모", "처리 설명", "수정 설명",
        ]
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
        value = value.replacingOccurrences(
            of: #"^\d+[.)]\s+"#,
            with: "",
            options: .regularExpression
        )

        while let first = value.first, "#*-_` ".contains(first) {
            value.removeFirst()
        }
        while let last = value.last, "*-_` ".contains(last) {
            value.removeLast()
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimSection(_ lines: [String]) -> String {
        var trimmed = lines
        while let first = trimmed.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRule(first) {
            trimmed.removeFirst()
        }
        while let last = trimmed.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRule(last) {
            trimmed.removeLast()
        }
        return trimmed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripWrappingCodeFence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2,
              isOpeningCodeFence(lines[0]),
              isClosingCodeFence(lines[lines.count - 1]) else {
            return trimmed
        }

        return trimSection(Array(lines.dropFirst().dropLast()))
    }

    static func isOpeningCodeFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "```" || trimmed.range(of: #"^```[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    static func isClosingCodeFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == "```"
    }

    static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }
}
