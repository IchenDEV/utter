#!/usr/bin/env swift
//
// generate-icon.swift
// Builds the medical offline app's Icon Composer, PNG, and ICNS assets.
//
// Usage:
//   swift scripts/generate-icon.swift --refresh-assets [resources-directory]


import AppKit
import Foundation

enum IconAppearance: CaseIterable {
    case light
    case dark

    var foregroundName: String {
        switch self {
        case .light: "AppIconLightForeground.png"
        case .dark: "AppIconDarkForeground.png"
        }
    }

    var pngName: String {
        switch self {
        case .light: "AppIconLight.png"
        case .dark: "AppIconDark.png"
        }
    }

    var icnsName: String {
        switch self {
        case .light: "AppIconLight.icns"
        case .dark: "AppIconDark.icns"
        }
    }

    var topColor: NSColor {
        switch self {
        case .light: NSColor(srgbRed: 0.97, green: 1.00, blue: 0.99, alpha: 1)
        case .dark: NSColor(srgbRed: 0.10, green: 0.17, blue: 0.18, alpha: 1)
        }
    }

    var bottomColor: NSColor {
        switch self {
        case .light: NSColor(srgbRed: 0.83, green: 0.93, blue: 0.92, alpha: 1)
        case .dark: NSColor(srgbRed: 0.025, green: 0.06, blue: 0.07, alpha: 1)
        }
    }

    var borderColor: NSColor {
        switch self {
        case .light: NSColor.white.withAlphaComponent(0.78)
        case .dark: NSColor.white.withAlphaComponent(0.18)
        }
    }

    var shieldColors: (bottom: NSColor, top: NSColor) {
        switch self {
        case .light:
            (
                NSColor(srgbRed: 0.035, green: 0.42, blue: 0.56, alpha: 1),
                NSColor(srgbRed: 0.12, green: 0.78, blue: 0.67, alpha: 1)
            )
        case .dark:
            (
                NSColor(srgbRed: 0.035, green: 0.48, blue: 0.62, alpha: 1),
                NSColor(srgbRed: 0.22, green: 0.90, blue: 0.76, alpha: 1)
            )
        }
    }
}

func projectDirectory() -> URL {
    URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func savePNG(_ image: NSImage, to url: URL, pixelSize: Int) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

func renderMedicalForeground(appearance: IconAppearance, size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        let scale = size / 1024
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale, y: y * scale)
        }
        func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGPath {
            let box = CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
            return CGPath(roundedRect: box, cornerWidth: min(box.width, box.height) * 0.28,
                          cornerHeight: min(box.width, box.height) * 0.28, transform: nil)
        }

        let shield = CGMutablePath()
        shield.move(to: point(304, 794))
        shield.addCurve(to: point(226, 716), control1: point(261, 794), control2: point(226, 759))
        shield.addLine(to: point(226, 478))
        shield.addCurve(to: point(512, 172), control1: point(226, 321), control2: point(360, 218))
        shield.addCurve(to: point(798, 478), control1: point(664, 218), control2: point(798, 321))
        shield.addLine(to: point(798, 716))
        shield.addCurve(to: point(720, 794), control1: point(798, 759), control2: point(763, 794))
        shield.closeSubpath()

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 24 * scale,
                          color: NSColor.black.withAlphaComponent(0.30).cgColor)
        context.addPath(shield)
        context.setFillColor(appearance.shieldColors.bottom.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shield)
        context.clip()
        let colors = appearance.shieldColors
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [colors.bottom.cgColor, colors.top.cgColor] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: point(512, 180), end: point(512, 800), options: [])
        context.restoreGState()

        context.addPath(shield)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.38).cgColor)
        context.setLineWidth(8 * scale)
        context.strokePath()

        context.setFillColor(NSColor.white.cgColor)
        context.addPath(roundedRect(474, 548, 76, 202))
        context.addPath(roundedRect(411, 611, 202, 76))
        context.fillPath()

        let bars: [(CGFloat, CGFloat)] = [(356, 58), (416, 102), (476, 142), (536, 102), (596, 58)]
        for (x, height) in bars {
            context.addPath(roundedRect(x, 332, 40, height))
        }
        context.setFillColor(NSColor.white.withAlphaComponent(0.94).cgColor)
        context.fillPath()
        return true
    }
}

func renderIcon(foreground: NSImage, appearance: IconAppearance, size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        context.clear(rect)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let background = rect.insetBy(dx: size * 0.078, dy: size * 0.078)
        let radius = background.width * 0.245
        let path = CGPath(
            roundedRect: background,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -size * 0.018),
            blur: size * 0.035,
            color: NSColor.black.withAlphaComponent(appearance == .dark ? 0.48 : 0.24).cgColor
        )
        context.setFillColor(appearance.bottomColor.cgColor)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.clip()
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [appearance.bottomColor.cgColor, appearance.topColor.cgColor] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: background.midX, y: background.minY),
            end: CGPoint(x: background.midX, y: background.maxY),
            options: []
        )
        context.restoreGState()

        context.setStrokeColor(appearance.borderColor.cgColor)
        context.setLineWidth(size * 0.006)
        context.addPath(path)
        context.strokePath()

        foreground.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        return true
    }
}

func writeICNS(_ image: NSImage, to outputURL: URL) throws {
    let fileManager = FileManager.default
    let iconsetURL = fileManager.temporaryDirectory
        .appendingPathComponent("UtterAppIcon-\(UUID().uuidString).iconset")
    try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: iconsetURL) }

    let sizes: [(String, Int)] = [
        ("icon_16x16", 16),
        ("icon_16x16@2x", 32),
        ("icon_32x32", 32),
        ("icon_32x32@2x", 64),
        ("icon_128x128", 128),
        ("icon_128x128@2x", 256),
        ("icon_256x256", 256),
        ("icon_256x256@2x", 512),
        ("icon_512x512", 512),
        ("icon_512x512@2x", 1024),
    ]
    for (name, pixels) in sizes {
        try savePNG(image, to: iconsetURL.appendingPathComponent("\(name).png"), pixelSize: pixels)
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        throw NSError(
            domain: "UtterIconGeneration",
            code: Int(task.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "iconutil failed"]
        )
    }
}

func refreshAssets(in resourcesURL: URL) throws {
    let foregroundsURL = resourcesURL
        .appendingPathComponent("AppIcon.icon")
        .appendingPathComponent("Assets")
    var rendered: [IconAppearance: NSImage] = [:]

    for appearance in IconAppearance.allCases {
        let sourceURL = foregroundsURL.appendingPathComponent(appearance.foregroundName)
        let foreground = renderMedicalForeground(appearance: appearance, size: 1024)
        try savePNG(foreground, to: sourceURL, pixelSize: 1024)
        let image = renderIcon(foreground: foreground, appearance: appearance, size: 1024)
        rendered[appearance] = image
        try savePNG(image, to: resourcesURL.appendingPathComponent(appearance.pngName), pixelSize: 1024)
        try writeICNS(image, to: resourcesURL.appendingPathComponent(appearance.icnsName))
    }

    guard let light = rendered[.light] else { return }
    try savePNG(light, to: resourcesURL.appendingPathComponent("AppIcon.png"), pixelSize: 1024)
    try writeICNS(light, to: resourcesURL.appendingPathComponent("AppIcon.icns"))
}

do {
    guard CommandLine.arguments.dropFirst().first == "--refresh-assets" else {
        fputs("Usage: swift scripts/generate-icon.swift --refresh-assets [resources-directory]\n", stderr)
        exit(1)
    }
    let resourcesURL = CommandLine.arguments.count > 2
        ? URL(fileURLWithPath: CommandLine.arguments[2])
        : projectDirectory().appendingPathComponent("Sources/Resources")
    try refreshAssets(in: resourcesURL)
    print("Utter Medical Offline icon assets refreshed in \(resourcesURL.path)")
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
