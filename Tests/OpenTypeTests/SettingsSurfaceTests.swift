import AppKit
import SwiftUI
import XCTest
@testable import OpenType

/// Verifies the settings surfaces through the SwiftUI `Color` values the app
/// actually renders, so swapping `page` and `card` (or recoloring either) fails.
///
/// Rasterizing happens in an `NSHostingView`, the same view hierarchy the
/// settings window uses, with an explicit `appearance` set. That makes light and
/// dark deterministic and independent of the process appearance, unlike
/// `ImageRenderer`, which follows the ambient appearance and ignored
/// `performAsCurrentDrawingAppearance`.
@MainActor
final class SettingsSurfaceTests: XCTestCase {
    func testPageSurfaceRendersAsWindowBackgroundColor() {
        assertSurface(SettingsSurface.page, matches: Color(nsColor: .windowBackgroundColor), label: "page")
    }

    func testCardSurfaceRendersAsUnderPageBackgroundColor() {
        assertSurface(SettingsSurface.card, matches: Color(nsColor: .underPageBackgroundColor), label: "card")
    }

    func testCardDoesNotRenderAsWindowBackgroundColor() throws {
        for appearance in Self.appearances {
            let card = try render(SettingsSurface.card, in: appearance)
            let page = try render(Color(nsColor: .windowBackgroundColor), in: appearance)
            XCTAssertFalse(
                isApproximatelyEqual(card, page),
                "card must not render as windowBackgroundColor in \(appearance.name.rawValue)"
            )
        }
    }

    func testPageAndCardSeparateVisibly() throws {
        for appearance in Self.appearances {
            let page = try render(SettingsSurface.page, in: appearance)
            let card = try render(SettingsSurface.card, in: appearance)
            let delta = abs(page.redComponent - card.redComponent)
                + abs(page.greenComponent - card.greenComponent)
                + abs(page.blueComponent - card.blueComponent)
            XCTAssertGreaterThan(
                delta,
                0.005,
                "boxes must separate from the page in \(appearance.name.rawValue)"
            )
        }
    }

    func testAppearancesProduceDistinctRenderings() throws {
        let light = try render(SettingsSurface.page, in: NSAppearance(named: .aqua)!)
        let dark = try render(SettingsSurface.page, in: NSAppearance(named: .darkAqua)!)
        XCTAssertGreaterThan(
            abs(light.redComponent - dark.redComponent),
            0.1,
            "light and dark must render the page differently"
        )
    }

    /// Pins the two seams to their semantic roles so a future edit is caught
    /// even when the colors are re-derived.
    func testSurfaceIdentitiesAreTheTwoSemanticRoles() {
        XCTAssertEqual(
            SettingsSurface.pageSemanticColor,
            NSColor.windowBackgroundColor,
            "page must be the window background role"
        )
        XCTAssertEqual(
            SettingsSurface.cardSemanticColor,
            NSColor.underPageBackgroundColor,
            "card must be the under-page background role"
        )
        XCTAssertNotEqual(
            SettingsSurface.pageSemanticColor,
            SettingsSurface.cardSemanticColor,
            "the two roles must not collapse onto one color"
        )
    }

    // MARK: - Helpers

    private static var appearances: [NSAppearance] {
        [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!]
    }

    private func assertSurface(
        _ color: Color,
        matches reference: @autoclosure () -> Color,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for appearance in Self.appearances {
            guard let actual = try? render(color, in: appearance),
                  let expected = try? render(reference(), in: appearance) else {
                XCTFail("\(label): could not render in \(appearance.name.rawValue)", file: file, line: line)
                continue
            }
            XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.02, "\(label) red", file: file, line: line)
            XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.02, "\(label) green", file: file, line: line)
            XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.02, "\(label) blue", file: file, line: line)
        }
    }

    private func render(_ color: Color, in appearance: NSAppearance) throws -> NSColor {
        let size: CGFloat = 10
        let hosting = NSHostingView(rootView: color.frame(width: size, height: size))
        hosting.appearance = appearance
        hosting.frame = NSRect(x: 0, y: 0, width: size, height: size)
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw RenderError.noBitmap
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let sampled = rep.colorAt(x: Int(size / 2), y: Int(size / 2)),
              let srgb = sampled.usingColorSpace(.sRGB) else {
            throw RenderError.noPixel
        }
        return srgb
    }

    private func isApproximatelyEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        abs(lhs.redComponent - rhs.redComponent) < 0.02
            && abs(lhs.greenComponent - rhs.greenComponent) < 0.02
            && abs(lhs.blueComponent - rhs.blueComponent) < 0.02
    }

    private enum RenderError: Error {
        case noBitmap
        case noPixel
    }
}
