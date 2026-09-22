import AppKit
import UncialCore

/// The callout icons for the editor: the page's Lucide SVGs (`Callouts.icon(for:)`) loaded through
/// `NSImage` with the color written in place of `currentColor`, cached per type, color and size.
enum CalloutIcons {
    private static var cache: [String: NSImage] = [:]

    static func image(for type: String, color: NSColor, size: CGFloat) -> NSImage? {
        let hex = hexString(color)
        let key = "\(Callouts.kind(for: type).icon)|\(hex)|\(size)"
        if let cached = cache[key] { return cached }
        let svg = Callouts.icon(for: type).replacingOccurrences(of: "currentColor", with: hex)
        guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.size = NSSize(width: size, height: size)
        cache[key] = image
        return image
    }

    private static func hexString(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02x%02x%02x", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}
