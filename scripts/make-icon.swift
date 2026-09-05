#!/usr/bin/env swift
// Generates the AppIcon set: a rounded dark tile with an uncial-style "U".
// Usage: swift scripts/make-icon.swift uncial/Assets.xcassets/AppIcon.appiconset
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let inset = size * 0.09
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: size * 0.2, yRadius: size * 0.2)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.22, green: 0.27, blue: 0.40, alpha: 1),
        ending: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.17, alpha: 1)
    )!
    gradient.draw(in: path, angle: -90)
    let font = NSFont(name: "Baskerville-Bold", size: size * 0.66) ?? NSFont.systemFont(ofSize: size * 0.6, weight: .bold)
    let letter = NSAttributedString(string: "U", attributes: [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.86, alpha: 1),
    ])
    let textSize = letter.size()
    letter.draw(at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2 + size * 0.03))
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
