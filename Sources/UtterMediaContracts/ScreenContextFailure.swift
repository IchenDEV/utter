import Foundation
import UtterContracts

package struct ScreenContextFailure: LocalizedError, SessionFailurePresenting {
    package let status: ScreenContextSnapshot.Status
    package init(status: ScreenContextSnapshot.Status) { self.status = status }
    package var errorDescription: String? {
        L(status == .permissionDenied ? "screen.permission_required"
            : status == .recognitionFailed ? "screen.recognition_failed" : "screen.capture_failed")
    }
    package var sessionFailure: SessionFailurePresentation {
        SessionFailurePresentation(message: localizedDescription,
            recovery: status == .permissionDenied ? .screenPrivacy : nil)
    }
}
