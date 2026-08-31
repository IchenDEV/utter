import Foundation

enum IntegrationError: Error, Equatable {
    struct Payload: Codable, Equatable {
        let error: String
        let message: String
    }

    case developerInterfaceDisabled
    case unauthorizedClient
    case busy
    case modelNotReady
    case permissionDenied
    case sessionNotFound
    case sessionCancelled
    case invalidSessionState
    case noSpeechDetected
    case operationFailed
    case operationFailedWithMessage(String)

    var payload: Payload {
        switch self {
        case .developerInterfaceDisabled:
            return Payload(error: "developer_interface_disabled", message: "Developer interface is disabled.")
        case .unauthorizedClient:
            return Payload(error: "unauthorized_client", message: "This app is not allowed to use Utter.")
        case .busy:
            return Payload(error: "busy", message: "Another input session is active.")
        case .modelNotReady:
            return Payload(error: "model_not_ready", message: "Speech model is not ready.")
        case .permissionDenied:
            return Payload(error: "permission_denied", message: "Microphone permission is required.")
        case .sessionNotFound:
            return Payload(error: "session_not_found", message: "Input session was not found.")
        case .sessionCancelled:
            return Payload(error: "session_cancelled", message: "Input session was cancelled.")
        case .invalidSessionState:
            return Payload(error: "invalid_session_state", message: "Input session is not in a valid state for this operation.")
        case .noSpeechDetected:
            return Payload(error: "no_speech_detected", message: "No speech was detected in the recording.")
        case .operationFailed:
            return Payload(error: "operation_failed", message: "Utter could not complete the input session.")
        case .operationFailedWithMessage(let message):
            return Payload(error: "operation_failed", message: message)
        }
    }
}
