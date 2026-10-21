#!/usr/bin/env swift
// Regenerates App/Resources/Assets.xcassets/AppIcon.appiconset (PNGs + Contents.json).
// Usage: swift Scripts/generate-app-icon.swift   (run from the repo root)
import AppKit

let outDir = "App/Resources/Assets.xcassets/AppIcon.appiconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

/// Draws the icon on a 1024-unit canvas, scaled to `pixels`.
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let s = CGFloat(pixels) / 1024
    let cg = ctx.cgContext
    cg.scaleBy(x: s, y: s)

    // Squircle body: 824pt square centered in the 1024 canvas (Apple template).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 24,
                 color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill()
    squircle.fill()
    cg.restoreGState()

    NSGradient(colors: [
        NSColor(srgbRed: 0.40, green: 0.47, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.18, blue: 0.78, alpha: 1),
    ])!.draw(in: squircle, angle: -90)

    // Subtle top highlight.
    cg.saveGState()
    squircle.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
    cg.restoreGState()

    // 2x2 grid of rounded squares.
    let side: CGFloat = 220, gap: CGFloat = 60
    let origin = (1024 - 2 * side - gap) / 2
    NSColor.white.setFill()
    for row in 0..<2 {
        for col in 0..<2 {
            let r = NSRect(x: origin + CGFloat(col) * (side + gap),
                           y: origin + CGFloat(row) * (side + gap), width: side, height: side)
            NSBezierPath(roundedRect: r, xRadius: 54, yRadius: 54).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: base * scale).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(base)x\(base)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
