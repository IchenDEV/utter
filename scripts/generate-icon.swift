#!/usr/bin/env swift
//
// generate-icon.swift
// Builds Utter PNG and .icns assets from the light/dark Icon Composer foregrounds.
//
// Usage:
//   swift scripts/generate-icon.swift --refresh-assets [resources-directory]
//   swift scripts/generate-icon.swift <output-directory> [source-png]


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
        case .light: NSColor(srgbRed: 0.99, green: 1.00, blue: 1.00, alpha: 1)
        case .dark: NSColor(srgbRed: 0.24, green: 0.25, blue: 0.27, alpha: 1)
        }
    }

    var bottomColor: NSColor {
        switch self {
        case .light: NSColor(srgbRed: 0.89, green: 0.91, blue: 0.95, alpha: 1)
        case .dark: NSColor(srgbRed: 0.055, green: 0.06, blue: 0.075, alpha: 1)
        }
    }

    var borderColor: NSColor {
        switch self {
        case .light: NSColor.white.withAlphaComponent(0.78)
        case .dark: NSColor.white.withAlphaComponent(0.18)
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
        guard let foreground = NSImage(contentsOf: sourceURL) else {
            throw NSError(
                domain: "UtterIconGeneration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not read \(sourceURL.path)"]
            )
        }
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
    if CommandLine.arguments.dropFirst().first == "--refresh-assets" {
        let resourcesURL = CommandLine.arguments.count > 2
            ? URL(fileURLWithPath: CommandLine.arguments[2])
            : projectDirectory().appendingPathComponent("Sources/Resources")
        try refreshAssets(in: resourcesURL)
        print("Utter app icon assets refreshed in \(resourcesURL.path)")
    } else {
        guard CommandLine.arguments.count > 1 else {
            fputs("Usage: swift scripts/generate-icon.swift --refresh-assets [resources-directory]\n", stderr)
            exit(1)
        }
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let sourceURL = CommandLine.arguments.count > 2
            ? URL(fileURLWithPath: CommandLine.arguments[2])
            : projectDirectory().appendingPathComponent("Sources/Resources/AppIcon.png")
        guard let icon = NSImage(contentsOf: sourceURL) else {
            throw NSError(
                domain: "UtterIconGeneration",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not read \(sourceURL.path)"]
            )
        }
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try writeICNS(icon, to: outputURL.appendingPathComponent("AppIcon.icns"))
        print("AppIcon.icns -> \(outputURL.path)")
    }
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
