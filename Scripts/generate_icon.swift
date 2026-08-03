#!/usr/bin/env swift
// Renders the NeoNotes app icon master (1024x1024) to the given output path.
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let canvas: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gc
let ctx = gc.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// --- Background squircle ---
let inset: CGFloat = 100
let bgRect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.addPath(bgPath)
ctx.setFillColor(color(0x161D33))
ctx.fillPath()

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

// --- Neon glyph: note card + text lines ---
let cardWidth: CGFloat = 384
let cardHeight: CGFloat = 448
let cardRect = CGRect(
    x: (canvas - cardWidth) / 2,
    y: (canvas - cardHeight) / 2,
    width: cardWidth,
    height: cardHeight
)
let strokeWidth: CGFloat = 26
let cardOutline = CGPath(roundedRect: cardRect, cornerWidth: 60, cornerHeight: 60, transform: nil)
    .copy(strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)

let glyph = CGMutablePath()
glyph.addPath(cardOutline)

let lineHeight: CGFloat = 30
let lineX = cardRect.minX + 76
let lineWidths: [CGFloat] = [232, 232, 148]
let lineSpacing: CGFloat = 84
let firstLineY = cardRect.maxY - 118
for (i, width) in lineWidths.enumerated() {
    let y = firstLineY - CGFloat(i) * lineSpacing
    glyph.addPath(CGPath(
        roundedRect: CGRect(x: lineX, y: y - lineHeight / 2, width: width, height: lineHeight),
        cornerWidth: lineHeight / 2,
        cornerHeight: lineHeight / 2,
        transform: nil
    ))
}

// Flat gradient fill over the glyph
ctx.saveGState()
ctx.addPath(glyph)
ctx.clip()
let glyphGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x38E1FF), color(0x8B7CFF), color(0xFF5FD2)] as CFArray,
    locations: [0, 0.5, 1]
)!
ctx.drawLinearGradient(
    glyphGradient,
    start: CGPoint(x: cardRect.minX - 40, y: cardRect.maxY + 40),
    end: CGPoint(x: cardRect.maxX + 40, y: cardRect.minY - 40),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
ctx.restoreGState()

ctx.restoreGState() // background clip
NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
