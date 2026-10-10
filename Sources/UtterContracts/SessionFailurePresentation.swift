import Foundation

package enum SessionRecoveryAction: String, Codable, Sendable {
    case models, microphonePrivacy, accessibilityPrivacy, screenPrivacy, speechPrivacy
}

package protocol SessionFailurePresenting {
    var sessionFailure: SessionFailurePresentation { get }
}

package struct SessionFailurePresentation: Equatable, Sendable {
    package let message: String
    package let recovery: SessionRecoveryAction?
    package init(message: String, recovery: SessionRecoveryAction? = nil) {
        self.message = message; self.recovery = recovery
    }
    package init(error: Error) {
        if let error = error as? any SessionFailurePresenting { self = error.sessionFailure; return }
        switch error {
        case IntegrationError.modelNotReady, GenerationServiceError.modelUnavailable, GenerationServiceError.modelChanged:
            self.init(message: L("pipeline.model_load_failed"), recovery: .models)
        case IntegrationError.permissionDenied:
            self.init(message: L("pipeline.mic_failed_permissions"), recovery: .microphonePrivacy)
        case IntegrationError.busy: self.init(message: L("pipeline.busy"))
        case IntegrationError.noSpeechDetected: self.init(message: L("status.no_speech_detected"))
        case let error as URLError: self.init(message: error.code == .cancelled
            ? L("error.operation_failed") : L("error.network_request_failed"))
        default: self.init(message: L("error.operation_failed"))
        }
    }
}

extension AudioCaptureStartFailure: SessionFailurePresenting {
    package var sessionFailure: SessionFailurePresentation {
        SessionFailurePresentation(message: localizedDescription,
            recovery: self == .permissionDenied ? .microphonePrivacy : nil)
    }
}
