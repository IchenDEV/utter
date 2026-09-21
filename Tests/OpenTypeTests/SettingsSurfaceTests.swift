import AppKit
import SwiftUI
import XCTest
@testable import OpenType

@MainActor
final class SettingsSurfaceTests: XCTestCase {
    func testPageSurfaceRendersWindowBackgroundColor() throws {
        try assertRendered(SettingsSurface.page, matches: .windowBackgroundColor)
    }

    func testCardSurfaceRendersUnderPageBackgroundColor() throws {
        try assertRendered(SettingsSurface.card, matches: .underPageBackgroundColor)
    }

    func testCardSurfaceIsDistinctFromPageSurface() throws {
        let page = try renderedColor(of: SettingsSurface.page)
        let card = try renderedColor(of: SettingsSurface.card)
        let delta = abs(page.redComponent - card.redComponent)
            + abs(page.greenComponent - card.greenComponent)
            + abs(page.blueComponent - card.blueComponent)
        XCTAssertGreaterThan(delta, 0.01, "Grouped boxes must separate from the page background")
    }

    private func assertRendered(
        _ color: Color,
        matches expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actual = try renderedColor(of: color)
        let target = try XCTUnwrap(expected.usingColorSpace(.sRGB), file: file, line: line)
        XCTAssertEqual(actual.redComponent, target.redComponent, accuracy: 0.03, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, target.greenComponent, accuracy: 0.03, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, target.blueComponent, accuracy: 0.03, file: file, line: line)
    }

    private func renderedColor(of color: Color) throws -> NSColor {
        let renderer = ImageRenderer(content: color.frame(width: 8, height: 8))
        renderer.scale = 1
        let cgImage = try XCTUnwrap(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let sampled = try XCTUnwrap(bitmap.colorAt(x: 4, y: 4))
        return try XCTUnwrap(sampled.usingColorSpace(.sRGB))
    }
}
