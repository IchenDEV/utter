#!/usr/bin/env swift

import AppKit
import Foundation

let canvasSize = CGSize(width: 680, height: 440)
let outputURL = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
let pixelScale = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) : 1

guard let outputURL, let pixelScale, (1...2).contains(pixelScale) else {
    fputs("Usage: swift scripts/generate-dmg-background.swift <output-png> [1|2]\n", stderr)
    exit(1)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width) * pixelScale,
    pixelsHigh: Int(canvasSize.height) * pixelScale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create the DMG background bitmap.\n", stderr)
    exit(1)
}

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("Could not create the DMG background graphics context.\n", stderr)
    exit(1)
}

context.translateBy(x: 0, y: canvasSize.height)
context.scaleBy(x: 1, y: -1)

let colorSpace = CGColorSpaceCreateDeviceRGB()
let background = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        NSColor(srgbRed: 0.975, green: 0.980, blue: 0.995, alpha: 1).cgColor,
        NSColor(srgbRed: 0.915, green: 0.930, blue: 0.970, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    background,
    start: CGPoint(x: canvasSize.width / 2, y: 0),
    end: CGPoint(x: canvasSize.width / 2, y: canvasSize.height),
    options: []
)

func drawGlow(center: CGPoint, color: NSColor, radius: CGFloat) {
    let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: .drawsAfterEndLocation
    )
}

drawGlow(
    center: CGPoint(x: 166, y: 266),
    color: NSColor(srgbRed: 0.34, green: 0.30, blue: 1, alpha: 0.10),
    radius: 230
)
drawGlow(
    center: CGPoint(x: 523, y: 260),
    color: NSColor(srgbRed: 0.22, green: 0.67, blue: 1, alpha: 0.075),
    radius: 230
)

context.setStrokeColor(NSColor.black.withAlphaComponent(0.045).cgColor)
context.setLineWidth(1)
for x in stride(from: CGFloat(0), through: canvasSize.width, by: 40) {
    context.move(to: CGPoint(x: x, y: 0))
    context.addLine(to: CGPoint(x: x, y: canvasSize.height))
}
for y in stride(from: CGFloat(0), through: canvasSize.height, by: 40) {
    context.move(to: CGPoint(x: 0, y: y))
    context.addLine(to: CGPoint(x: canvasSize.width, y: y))
}
context.strokePath()

func drawText(
    _ text: String,
    at point: CGPoint,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraphStyle,
    ]
    let string = NSString(string: text)
    let size = string.size(withAttributes: attributes)
    let x = alignment == .center ? point.x - size.width / 2 : point.x
    let rect = CGRect(origin: CGPoint(x: x, y: point.y), size: size)

    context.saveGState()
    context.translateBy(x: 0, y: rect.minY * 2 + rect.height)
    context.scaleBy(x: 1, y: -1)
    string.draw(in: rect, withAttributes: attributes)
    context.restoreGState()
}

let white = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.17, alpha: 1)
let secondary = NSColor(srgbRed: 0.39, green: 0.41, blue: 0.49, alpha: 1)
let accent = NSColor(srgbRed: 0.51, green: 0.48, blue: 1, alpha: 1)

context.setFillColor(accent.cgColor)
context.fillEllipse(in: CGRect(x: 40, y: 43, width: 10, height: 10))
drawText(
    "UTTER",
    at: CGPoint(x: 60, y: 35),
    font: .systemFont(ofSize: 20, weight: .bold),
    color: white
)
drawText(
    "macOS 26+  ·  Apple Silicon",
    at: CGPoint(x: 462, y: 40),
    font: .systemFont(ofSize: 12, weight: .medium),
    color: secondary
)

context.setStrokeColor(NSColor.black.withAlphaComponent(0.09).cgColor)
context.move(to: CGPoint(x: 40, y: 76))
context.addLine(to: CGPoint(x: 640, y: 76))
context.strokePath()

drawText(
    "Drag Utter to Applications",
    at: CGPoint(x: canvasSize.width / 2, y: 101),
    font: .systemFont(ofSize: 23, weight: .semibold),
    color: white,
    alignment: .center
)
drawText(
    "Install in one step",
    at: CGPoint(x: canvasSize.width / 2, y: 134),
    font: .systemFont(ofSize: 13, weight: .medium),
    color: secondary,
    alignment: .center
)

let arrowRect = CGRect(x: 289, y: 226, width: 102, height: 48)
let arrowBackground = CGPath(
    roundedRect: arrowRect,
    cornerWidth: 24,
    cornerHeight: 24,
    transform: nil
)
context.setFillColor(NSColor.black.withAlphaComponent(0.045).cgColor)
context.addPath(arrowBackground)
context.fillPath()
context.setStrokeColor(NSColor.black.withAlphaComponent(0.12).cgColor)
context.setLineWidth(1)
context.addPath(arrowBackground)
context.strokePath()

context.setStrokeColor(white.withAlphaComponent(0.88).cgColor)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setLineWidth(2.5)
context.move(to: CGPoint(x: 316, y: 250))
context.addLine(to: CGPoint(x: 365, y: 250))
context.move(to: CGPoint(x: 356, y: 241))
context.addLine(to: CGPoint(x: 365, y: 250))
context.addLine(to: CGPoint(x: 356, y: 259))
context.strokePath()

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the DMG background as PNG.\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: outputURL, options: .atomic)
    print("DMG background -> \(outputURL.path)")
} catch {
    fputs("Could not write the DMG background: \(error.localizedDescription)\n", stderr)
    exit(1)
}
