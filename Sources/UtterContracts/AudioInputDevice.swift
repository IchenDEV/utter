import Foundation

package struct AudioInputDevice: Equatable, Sendable {
    package let uid: String
    package let name: String
    package let isBuiltIn: Bool

    package init(uid: String, name: String, isBuiltIn: Bool) {
        self.uid = uid
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

package enum AudioCaptureStartFailure: Error, Equatable, LocalizedError {
    case permissionDenied
    case noUsableInput
    case engineFailed

    package var errorDescription: String? {
        switch self {
        case .permissionDenied: return L("pipeline.mic_failed_permissions")
        case .noUsableInput: return L("pipeline.mic_unavailable")
        case .engineFailed: return L("pipeline.mic_engine_failed")
        }
    }
}
