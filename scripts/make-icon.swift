#!/usr/bin/env swift
// Generates the AppIcon set from the app icon artwork: the rounded tile in static/icon.png is
// measured and cropped edge to edge (no margin, no baked shadow), its transparent corners filled
// with the tile's own edge colors so every PNG is a fully opaque square, then resampled into every
// size the asset catalog lists. macOS 26 and later mask such an icon into the system shape; an icon
// with margins or transparent corners is put on a backdrop tile instead (seen 2026-09-16).
// Usage: swift scripts/make-icon.swift static/icon.png uncial/Assets.xcassets/AppIcon.appiconset
import AppKit

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

guard let source = NSBitmapImageRep(data: try! Data(contentsOf: sourceURL)) else {
    fatalError("Cannot read \(sourceURL.path)")
}
let width = source.pixelsWide
let height = source.pixelsHigh

/// The opaque tile, found by walking the center row and column until the alpha drops: the tile's
/// drop shadow and antialiased corners are translucent, the tile itself is not.
func alpha(_ x: Int, _ y: Int) -> CGFloat {
    source.colorAt(x: x, y: y)?.alphaComponent ?? 0
}
let centerX = width / 2
let centerY = height / 2
var left = centerX
while left > 0, alpha(left - 1, centerY) > 0.97 { left -= 1 }
var right = centerX
while right < width - 1, alpha(right + 1, centerY) > 0.97 { right += 1 }
var top = centerY
while top > 0, alpha(centerX, top - 1) > 0.97 { top -= 1 }
// The shadow under the tile is opaque where it starts, so the column would overshoot: the tile is
// square, and its width and top edge are what count.
let tileSide = right - left + 1
// Source rectangles in AppKit's bottom-left coordinates.
let tile = NSRect(x: left, y: height - top - tileSide, width: tileSide, height: tileSide)
// The tile's edge color on every row, top to bottom, taken a few pixels inside the first opaque pixel
// from the left (the rounded corners start further in than the straight edge): painted across the
// canvas behind the tile, they continue its vertical gradient into the transparent corners.
let edgeColors: [NSColor] = (top..<(top + tileSide)).map { y in
    var x = left
    while x < right, alpha(x, y) <= 0.97 { x += 1 }
    return (source.colorAt(x: min(x + 3, right), y: y) ?? .black).withAlphaComponent(1)
}
print("Tile \(tileSide) px at (\(left), \(top))")

let image = NSImage(size: NSSize(width: width, height: height))
image.addRepresentation(source)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let target = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSImageInterpolation.high]
    // Bottom-left origin: output row 0 is the bottom of the tile.
    for row in 0..<pixels {
        let sourceRow = min(tileSide - 1, (pixels - 1 - row) * tileSide / pixels)
        edgeColors[sourceRow].setFill()
        NSRect(x: 0, y: row, width: pixels, height: 1).fill()
    }
    image.draw(in: target, from: tile, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: hints)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for variant in variants {
    let name = variant.scale == 1
        ? "icon_\(variant.points)x\(variant.points).png"
        : "icon_\(variant.points)x\(variant.points)@\(variant.scale)x.png"
    try! render(pixels: variant.points * variant.scale).write(to: outputDirectory.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(variant.scale)x", "size": "\(variant.points)x\(variant.points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outputDirectory.path)")
