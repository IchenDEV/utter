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

package enum AudioCaptureStartFailure: Error, Equatable {
    case permissionDenied
    case noUsableInput
    case engineFailed
}
