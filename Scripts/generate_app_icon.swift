import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate_app_icon.swift <output.png>\n".utf8))
    exit(2)
}

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    exit(1)
}

context.clear(CGRect(x: 0, y: 0, width: size, height: size))

let inset = 64.0
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let squircle = CGPath(roundedRect: rect, cornerWidth: 232, cornerHeight: 232, transform: nil)
context.addPath(squircle)
context.clip()

let colors = [
    NSColor(srgbRed: 0.36, green: 0.22, blue: 0.95, alpha: 1).cgColor,
    NSColor(srgbRed: 0.75, green: 0.20, blue: 0.95, alpha: 1).cgColor,
    NSColor(srgbRed: 0.95, green: 0.31, blue: 0.55, alpha: 1).cgColor,
] as CFArray
let locations: [CGFloat] = [0, 0.55, 1]
if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
}

if let glow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor.white.withAlphaComponent(0.35).cgColor,
        NSColor.white.withAlphaComponent(0).cgColor,
    ] as CFArray,
    locations: [0, 1]
) {
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: rect.midX - 180, y: rect.midY + 220),
        startRadius: 0,
        endCenter: CGPoint(x: rect.midX - 180, y: rect.midY + 220),
        endRadius: 620,
        options: []
    )
}

context.setFillColor(NSColor.white.withAlphaComponent(0.96).cgColor)
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.3).cgColor)
let triangle = CGMutablePath()
let centerX = rect.midX + 34
let centerY = rect.midY
triangle.move(to: CGPoint(x: centerX - 104, y: centerY + 152))
triangle.addLine(to: CGPoint(x: centerX - 104, y: centerY - 152))
triangle.addLine(to: CGPoint(x: centerX + 172, y: centerY))
triangle.closeSubpath()
context.addPath(triangle)
context.fillPath()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let representation = NSBitmapImageRep(data: tiff),
    let png = representation.representation(using: .png, properties: [:])
else {
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
