import Foundation

enum TextFormatKind: String, Codable, CaseIterable, Sendable {
    case plainParagraph
    case unorderedList
    case orderedSteps
    case email
    case chat
    case codeOrTerminal
}

struct TextFormatDecision: Equatable, Sendable {
    enum Reason: String, Sendable {
        case explicitSequence
        case explicitList
        case emailStructure
        case emailApplication
        case chatApplication
        case codeApplication
        case defaultParagraph
    }

    let kind: TextFormatKind
    let reason: Reason
}

enum TextFormatClassifier {
    static func classify(text: String, context: InputContext?) -> TextFormatDecision {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let applicationIdentity = [context?.bundleIdentifier, context?.appName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if matchesAny(codeAppPatterns, in: applicationIdentity) {
            return TextFormatDecision(kind: .codeOrTerminal, reason: .codeApplication)
        }

        if hasExplicitSequence(normalized) {
            return TextFormatDecision(kind: .orderedSteps, reason: .explicitSequence)
        }
        if matchesAny(explicitListPatterns, in: normalized) {
            return TextFormatDecision(kind: .unorderedList, reason: .explicitList)
        }
        if hasEmailStructure(normalized) {
            return TextFormatDecision(kind: .email, reason: .emailStructure)
        }

        let target = [context?.bundleIdentifier, context?.appName, context?.windowTitle]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if matchesAny(emailAppPatterns, in: target) {
            return TextFormatDecision(kind: .email, reason: .emailApplication)
        }
        if matchesAny(chatAppPatterns, in: target) {
            return TextFormatDecision(kind: .chat, reason: .chatApplication)
        }
        return TextFormatDecision(kind: .plainParagraph, reason: .defaultParagraph)
    }
}

private extension TextFormatClassifier {
    static let explicitListPatterns = [
        "购物清单", "采购清单", "待办清单", "列个清单", "列一下", "清单包括",
        "有几件事", "有三件事", "有四件事", "主要包括", "分别是",
        "shopping list", "grocery list", "todo list", "to-do list", "the list includes",
        "here are the items", "there are three things", "key points are",
        "買い物リスト", "チェックリスト", "목록", "장보기 목록",
    ]
    static let emailAppPatterns = [
        "com.apple.mail", "outlook", "thunderbird", "spark", "airmail", "gmail",
    ]
    static let chatAppPatterns = [
        "slack", "discord", "messages", "whatsapp", "telegram", "wechat", "weixin",
        "lark", "feishu", "teams", "signal", "line",
    ]
    static let codeAppPatterns = [
        "terminal", "iterm", "warp", "ghostty", "alacritty", "wezterm", "xcode",
        "visual studio code", "vscode", "zed", "sublime text", "jetbrains",
    ]

    static func hasExplicitSequence(_ text: String) -> Bool {
        let groups = [
            ["第一", "首先", "第一步", "一是"],
            ["第二", "其次", "第二步", "二是"],
            ["first", "firstly", "first step", "step one"],
            ["second", "secondly", "second step", "step two"],
            ["まず", "第一", "ステップ1"],
            ["次に", "第二", "ステップ2"],
            ["첫째", "먼저", "1단계"],
            ["둘째", "다음", "2단계"],
        ]
        let chineseOrEnglish = groups[0].contains(where: text.contains)
            && groups[1].contains(where: text.contains)
            || groups[2].contains(where: { containsWord($0, in: text) })
            && groups[3].contains(where: { containsWord($0, in: text) })
        let japanese = groups[4].contains(where: text.contains) && groups[5].contains(where: text.contains)
        let korean = groups[6].contains(where: text.contains) && groups[7].contains(where: text.contains)
        return chineseOrEnglish || japanese || korean
    }

    static func hasEmailStructure(_ text: String) -> Bool {
        let greetings = ["hi ", "hello ", "dear ", "hey ", "你好", "您好", "嗨", "亲爱的", "こんにちは", "안녕하세요"]
        let closings = ["thanks", "thank you", "regards", "best", "sincerely", "谢谢", "感谢", "祝好", "此致", "よろしく", "감사합니다"]
        return greetings.contains(where: text.hasPrefix)
            && closings.contains(where: text.contains)
    }

    static func matchesAny(_ patterns: [String], in text: String) -> Bool {
        patterns.contains(where: text.contains)
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        text.range(
            of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
