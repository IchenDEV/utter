import Foundation
import CoreGraphics

package struct ScreenContextSnapshot: @unchecked Sendable {
    package let text: String
    package let image: CGImage?

    package init(text: String, image: CGImage?) {
        self.text = text
        self.image = image
    }

    package static let empty = ScreenContextSnapshot(text: "", image: nil)
}

