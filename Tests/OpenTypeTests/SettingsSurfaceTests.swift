import AppKit
import SwiftUI
import XCTest
@testable import OpenType

@MainActor
final class SettingsSurfaceTests: XCTestCase {
    /// The seams must be the system colors. Assertions resolve both sides
    /// through the sRGB color space instead of comparing rendered pixels: a
    /// headless runner resolves the semantic colors through a different color
    /// pipeline than a user session, so pixel comparisons produce false
    /// failures.
    func testPageSurfaceUsesWindowBackgroundColor() {
        assertComponent(
            SettingsSurface.pageSRGB,
            matches: .windowBackgroundColor,
            label: "page"
        )
    }

    func testCardSurfaceUsesUnderPageBackgroundColor() {
        assertComponent(
            SettingsSurface.cardSRGB,
            matches: .underPageBackgroundColor,
            label: "card"
        )
    }

    func testSurfacesUseDifferentSemanticColors() throws {
        let expectedPage = try XCTUnwrap(NSColor.windowBackgroundColor.usingColorSpace(.sRGB))
        let expectedCard = try XCTUnwrap(NSColor.underPageBackgroundColor.usingColorSpace(.sRGB))
        XCTAssertNotEqual(
            expectedPage.redComponent,
            expectedCard.redComponent,
            "windowBackgroundColor and underPageBackgroundColor must differ"
        )
        XCTAssertGreaterThan(
            abs(expectedPage.redComponent - expectedCard.redComponent),
            0.01,
            "Grouped boxes must visibly separate from the page background"
        )
    }

    func testSurfacesResolveInsideExplicitAppearances() {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = appearanceName
            var expectedPage = NSColor.windowBackgroundColor
            var expectedCard = NSColor.underPageBackgroundColor
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                expectedPage = NSColor.windowBackgroundColor
                expectedCard = NSColor.underPageBackgroundColor
            }
            XCTAssertEqual(
                SettingsSurface.pageSRGB.redComponent,
                expectedPage.usingColorSpace(.sRGB)?.redComponent ?? -1,
                accuracy: 0.03,
                "page in \(appearance.rawValue)"
            )
            XCTAssertEqual(
                SettingsSurface.cardSRGB.redComponent,
                expectedCard.usingColorSpace(.sRGB)?.redComponent ?? -1,
                accuracy: 0.03,
                "card in \(appearance.rawValue)"
            )
        }
    }

    private func assertComponent(
        _ color: NSColor,
        matches expected: NSColor,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual = color.usingColorSpace(.sRGB),
              let target = expected.usingColorSpace(.sRGB) else {
            XCTFail("\(label): could not resolve sRGB components", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.redComponent, target.redComponent, accuracy: 0.03, "\(label) red", file: file, line: line)
        XCTAssertEqual(actual.greenComponent, target.greenComponent, accuracy: 0.03, "\(label) green", file: file, line: line)
        XCTAssertEqual(actual.blueComponent, target.blueComponent, accuracy: 0.03, "\(label) blue", file: file, line: line)
    }
}
