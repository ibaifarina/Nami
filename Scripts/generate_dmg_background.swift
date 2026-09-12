#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Generates the disk-image background used by Scripts/make_dmg.sh.
// Usage: swift generate_dmg_background.swift <out.png> [width] [height]

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(
        Data("usage: generate_dmg_background.swift <out.png> [width] [height]\n".utf8)
    )
    exit(1)
}

let outputPath = arguments[1]
let width = arguments.count > 2 ? (Int(arguments[2]) ?? 660) : 660
let height = arguments.count > 3 ? (Int(arguments[3]) ?? 420) : 420
let scale = 2

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width * scale,
    pixelsHigh: height * scale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("could not allocate bitmap\n".utf8))
    exit(1)
}
bitmap.size = NSSize(width: width, height: height)

guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("could not create graphics context\n".utf8))
    exit(1)
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
// `bitmap.size` is in points while the backing store is `scale`x pixels, so
// the graphics context already maps logical points to Retina pixels.
let context = graphics.cgContext

let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
let colorSpace = CGColorSpaceCreateDeviceRGB()

// Base background: the app's light surface (#FFFFFF -> #F2F2F5).
let background = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(0xFFFFFF), rgb(0xF2F2F5)] as CFArray,
    locations: [0, 1]
)!
context.saveGState()
context.addRect(bounds)
context.clip()
context.drawLinearGradient(
    background,
    start: CGPoint(x: 0, y: bounds.maxY),
    end: CGPoint(x: 0, y: 0),
    options: []
)
context.restoreGState()

// Soft sage glow behind the app icon, echoing the logo accent.
func glow(center: CGPoint, radius: CGFloat, color: CGColor) {
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color, rgb(0x000000, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.saveGState()
    context.addRect(bounds)
    context.clip()
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: []
    )
    context.restoreGState()
}

glow(
    center: CGPoint(x: CGFloat(width) * 0.28, y: CGFloat(height) * 0.5),
    radius: CGFloat(height) * 0.55,
    color: rgb(0x1C1C1E, 0.06)
)
glow(
    center: CGPoint(x: CGFloat(width) * 0.72, y: CGFloat(height) * 0.5),
    radius: CGFloat(height) * 0.5,
    color: rgb(0x1C1C1E, 0.04)
)

// Chevron pointing from the app to the Applications drop link.
context.setStrokeColor(rgb(0x000000, 0.5))
context.setLineWidth(3)
context.setLineCap(.round)
context.setLineJoin(.round)
let midX = CGFloat(width) / 2
let midY = CGFloat(height) / 2
context.beginPath()
context.move(to: CGPoint(x: midX - 14, y: midY + 16))
context.addLine(to: CGPoint(x: midX + 14, y: midY))
context.addLine(to: CGPoint(x: midX - 14, y: midY - 16))
context.strokePath()

// Wordmark and hint.
func drawCentered(_ text: String, y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    string.draw(at: NSPoint(x: (CGFloat(width) - size.width) / 2, y: y))
}

drawCentered(
    "Nami",
    y: CGFloat(height) - 82,
    attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
        .foregroundColor: NSColor(white: 0, alpha: 0.9),
        .kern: 1.5,
    ]
)
drawCentered(
    "Drag Nami to the Applications folder to install",
    y: 42,
    attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(white: 0, alpha: 0.5),
    ]
)

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode png\n".utf8))
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: outputPath))
} catch {
    FileHandle.standardError.write(Data("could not write \(outputPath): \(error)\n".utf8))
    exit(1)
}
