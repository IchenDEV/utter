import Foundation

package enum RemoteLLMError: LocalizedError {
    case noAPIKey
    case noBaseURL
    case requestFailed(String)
    case invalidResponse

    package var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API key not configured"
        case .noBaseURL: return "Base URL not configured"
        case .requestFailed(let msg): return "Request failed: \(msg)"
        case .invalidResponse: return "Invalid response from server"
        }
    }
}

