#!/usr/bin/env swift
//
// generate-social-card.swift
// Renders a 1200x630 OpenGraph/Twitter social card PNG for the landing page.
//
// Usage: swift generate-social-card.swift [output-png]
//   Default output: docs/assets/social-card.png (relative to repo root).
//

import AppKit
import Foundation

// MARK: - Main

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let projectDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputPath = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : projectDir.appendingPathComponent("docs/assets/social-card.png")
let iconPath = projectDir.appendingPathComponent("docs/assets/opentype-icon.png").path

guard let icon = NSImage(contentsOfFile: iconPath) else {
    fputs("Could not read icon: \(iconPath)\n", stderr)
    exit(1)
}

let W = 1200
let H = 630

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// AppKit origin is bottom-left; flip so we can think top-left.
ctx.translateBy(x: 0, y: CGFloat(H))
ctx.scaleBy(x: 1, y: -1)

// MARK: Background
let bg = NSColor(red: 0x10/255, green: 0x10/255, blue: 0x0F/255, alpha: 1).cgColor
ctx.setFillColor(bg)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

// Diagonal accent streaks (orange + blue), low alpha, like the hero.
let drawStreak = { (startX: CGFloat, alpha: CGFloat, color: NSColor) in
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(180)
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.move(to: NSPoint(x: startX, y: -40))
    path.line(to: NSPoint(x: startX + 360, y: CGFloat(H) + 40))
    path.stroke()
    ctx.restoreGState()
}
drawStreak(820, 0.10, NSColor(red: 1, green: 0.478, blue: 0.239, alpha: 1))   // #FF7A3D
drawStreak(980, 0.08, NSColor(red: 0.471, green: 0.788, blue: 1, alpha: 1))    // #78C9FF

// Subtle grid lines, very faint.
ctx.saveGState()
ctx.setAlpha(0.05)
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineWidth(1)
for x in stride(from: 0, to: W, by: 48) {
    ctx.move(to: CGPoint(x: CGFloat(x), y: 0))
    ctx.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(H)))
}
for y in stride(from: 0, to: H, by: 48) {
    ctx.move(to: CGPoint(x: 0, y: CGFloat(y)))
    ctx.addLine(to: CGPoint(x: CGFloat(W), y: CGFloat(y)))
}
ctx.strokePath()
ctx.restoreGState()

// MARK: Helpers
func drawText(_ text: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor, align: NSTextAlignment = .left) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color,
        .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = align; return p }()
    ]
    let str = NSString(string: text)
    let size = str.size(withAttributes: attrs)
    let originX = align == .right ? x - size.width : x
    let rect = CGRect(x: originX, y: y, width: size.width, height: size.height)
    ctx.saveGState()
    ctx.translateBy(x: 0, y: rect.minY * 2 + rect.height)
    ctx.scaleBy(x: 1, y: -1)
    str.draw(in: rect, withAttributes: attrs)
    ctx.restoreGState()
}

let serifBold = NSFont(name: "NewYork-Bold", size: 60)
    ?? NSFont(name: "IowanOldStyle-Bold", size: 60)
    ?? NSFont(name: "Georgia-Bold", size: 60)
    ?? NSFont.boldSystemFont(ofSize: 60)
let sansBold = NSFont(name: "AvenirNext-Bold", size: 40)
    ?? NSFont.boldSystemFont(ofSize: 40)
let monoBold = NSFont(name: "SFMono-Bold", size: 18)
    ?? NSFont(name: "Menlo-Bold", size: 18)
    ?? NSFont.boldSystemFont(ofSize: 18)
let sansReg = NSFont(name: "AvenirNext-Regular", size: 26)
    ?? NSFont.systemFont(ofSize: 26)

let paper = NSColor(red: 0xFA/255, green: 0xF8/255, blue: 0xED/255, alpha: 1)
let muted = NSColor(red: 0xC7/255, green: 0xC0/255, blue: 0xAD/255, alpha: 1)
let muted2 = NSColor(red: 0x8F/255, green: 0x88/255, blue: 0x77/255, alpha: 1)
let signal = NSColor(red: 0x39/255, green: 0xF3/255, blue: 0x9C/255, alpha: 1)
let paper2 = NSColor(red: 0xE7/255, green: 0xF1/255, blue: 0x5C/255, alpha: 1)

// MARK: Top row — icon + wordmark
let iconBox = 84
let iconX = 80
let iconY = 92
let iconRect = CGRect(x: iconX, y: iconY, width: iconBox, height: iconBox)
ctx.saveGState()
let clip = NSBezierPath(roundedRect: iconRect, xRadius: 18, yRadius: 18)
clip.addClip()
ctx.translateBy(x: 0, y: iconRect.minY * 2 + iconRect.height)
ctx.scaleBy(x: 1, y: -1)
icon.draw(in: iconRect)
ctx.restoreGState()

drawText("UTTER", x: CGFloat(iconX + iconBox + 22), y: CGFloat(iconY + 26), font: sansBold, color: paper)
drawText("FOR macOS", x: CGFloat(iconX + iconBox + 22), y: CGFloat(iconY + iconBox + 8), font: monoBold, color: muted2)

// MARK: Headline
drawText("Speak.", x: 80, y: 232, font: serifBold, color: paper)
let headline2 = NSFont(name: serifBold.fontName, size: 44) ?? serifBold
drawText("Your Mac types anywhere.", x: 80, y: 300, font: headline2, color: paper2)

// MARK: Subtitle (wrapped)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: sansReg, .foregroundColor: muted,
    .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = 4; return p }()
]
let sub = NSString(string: "Local AI voice input for macOS. Hold a key, speak naturally, and polished text appears at your cursor — on-device speech recognition and LLM cleanup.")
let subRect = CGRect(x: 80, y: 372, width: 1040, height: 90)
ctx.saveGState()
ctx.translateBy(x: 0, y: subRect.minY * 2 + subRect.height)
ctx.scaleBy(x: 1, y: -1)
sub.draw(in: subRect, withAttributes: subAttrs)
ctx.restoreGState()

// MARK: Capability rail
let rail = "LOCAL ASR   ·   ON-DEVICE CLEANUP   ·   SCREEN CONTEXT   ·   WORKS IN ANY APP"
drawText(rail, x: 80, y: 488, font: monoBold, color: muted2)

// MARK: Bottom strip — green dot + URL
ctx.setFillColor(signal.cgColor)
ctx.fillEllipse(in: CGRect(x: 82, y: 560, width: 10, height: 10))
drawText("utter.idevlab.dev", x: 104, y: 555, font: monoBold, color: paper2)
drawText("macOS 26+ · Apple Silicon · MIT licensed", x: CGFloat(W) - 80, y: 555, font: monoBold, color: muted2, align: .right)

NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
try! FileManager.default.createDirectory(at: outputPath.deletingLastPathComponent(), withIntermediateDirectories: true)
try! data.write(to: outputPath)
print("social card -> \(outputPath.path)")
