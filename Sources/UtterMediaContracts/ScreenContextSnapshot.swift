import Foundation
import CoreGraphics

package struct ScreenContextSnapshot: @unchecked Sendable {
    package enum Status: String, Sendable {
        case captured, noText, permissionDenied, captureFailed, recognitionFailed
    }
    package let text: String
    package let image: CGImage?
    package let status: Status

    package init(text: String, image: CGImage?, status: Status? = nil) {
        self.text = text
        self.image = image
        self.status = status ?? (text.isEmpty ? .noText : .captured)
    }

    package static let empty = ScreenContextSnapshot(text: "", image: nil)
}
