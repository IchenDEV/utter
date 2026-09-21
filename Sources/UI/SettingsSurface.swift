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
    /// Window and page background, matching the System Settings content pane.
    static var page: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    /// Grouped box and card background, subtly separated from the page.
    static var card: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    /// Hairline used to outline grouped boxes.
    static var cardStroke: Color {
        Color(nsColor: .separatorColor)
    }

    /// Resolved sRGB values for `page` and `card`, for tests and diagnostics that
    /// need the concrete components of the semantic colors.
    static var pageSRGB: NSColor {
        NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .windowBackgroundColor
    }

    static var cardSRGB: NSColor {
        NSColor.underPageBackgroundColor.usingColorSpace(.sRGB) ?? .underPageBackgroundColor
    }
}
