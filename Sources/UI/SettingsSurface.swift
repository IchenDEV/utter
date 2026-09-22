import AppKit
import SwiftUI

/// Shared semantic surfaces for the settings and onboarding windows.
///
/// macOS System Settings paints its content pane with `windowBackgroundColor`
/// and separates grouped boxes with a slightly offset fill. Utter previously did
/// the opposite — a gray page with white cards — which reads as an off-system
/// gray. These seams keep every surface on the system palette, so light, dark,
/// and increased-contrast appearances adapt without fixed colors.
enum SettingsSurface {
    /// The AppKit semantic colors the two seams are defined by. Kept as the
    /// single source of truth so the surfaces cannot drift from their roles.
    static var pageSemanticColor: NSColor { .windowBackgroundColor }
    static var cardSemanticColor: NSColor { .underPageBackgroundColor }

    /// Window and page background, matching the System Settings content pane.
    static var page: Color {
        Color(nsColor: pageSemanticColor)
    }

    /// Grouped box and card background, subtly separated from the page.
    static var card: Color {
        Color(nsColor: cardSemanticColor)
    }

    /// Hairline used to outline grouped boxes.
    static var cardStroke: Color {
        Color(nsColor: .separatorColor)
    }
}
