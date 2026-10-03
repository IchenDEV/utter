import Foundation

package enum ApiFormat: String, Codable {
    case openai
    case anthropic
}

package enum RemoteProvider: String, Codable, Identifiable {
    case custom
    case openai
    case claude
    case gemini
    case openrouter
    case siliconflow
    case doubao
    case bailian
    case minimax
    case minimaxGlobal

    package var id: String { rawValue }

    package static let allCases: [RemoteProvider] = [
        .custom, .openai, .claude, .gemini, .openrouter, .siliconflow,
        .doubao, .bailian, .minimax, .minimaxGlobal,
    ]

    package var displayName: String {
        switch self {
        case .custom: return L("remote.custom")
        case .openai: return "OpenAI"
        case .claude: return "Anthropic Claude"
        case .gemini: return "Google Gemini"
        case .openrouter: return "OpenRouter"
        case .siliconflow: return L("remote.siliconflow")
        case .doubao: return L("remote.doubao")
        case .bailian: return L("remote.bailian")
        case .minimax: return L("remote.minimax_cn")
        case .minimaxGlobal: return L("remote.minimax_global")
        }
    }

    /// Base URL including version prefix. Client appends `/chat/completions` or `/messages`.
    package var defaultBaseURL: String {
        switch self {
        case .custom: return ""
        case .openai: return "https://api.openai.com/v1"
        case .claude: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .siliconflow: return "https://api.siliconflow.cn/v1"
        case .doubao: return "https://ark.cn-beijing.volces.com/api/v3"
        case .bailian: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .minimax: return "https://api.minimax.chat/v1"
        case .minimaxGlobal: return "https://api.minimaxi.chat/v1"
        }
    }

    package var defaultModel: String {
        switch self {
        case .custom: return ""
        case .openai: return "gpt-4.1-mini"
        case .claude: return "claude-sonnet-4-6-20251001"
        case .gemini: return "gemini-2.5-flash"
        case .openrouter: return "google/gemini-2.5-flash"
        case .siliconflow: return "Qwen/Qwen3-30B-A3B"
        case .doubao: return "doubao-pro-32k-250428"
        case .bailian: return "qwen-plus"
        case .minimax: return "MiniMax-Text-01"
        case .minimaxGlobal: return "MiniMax-Text-01"
        }
    }

    package var apiFormat: ApiFormat {
        switch self {
        case .claude: return .anthropic
        default: return .openai
        }
    }

    /// Anthropic API version header, only used for `.anthropic` format.
    package var defaultApiVersion: String? {
        switch self {
        case .claude: return "2023-06-01"
        default: return nil
        }
    }
}
