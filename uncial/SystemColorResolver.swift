import AppKit
import UncialCore

/// The values of the WebKit system colors the stylesheets name (`Stylesheet.systemColorNames`), for a
/// page other browsers show (File ▸ Export… as HTML). WebKit draws `-apple-system-<name>` with these
/// `NSColor`s: in sRGB under Aqua and DarkAqua they equal its computed values (probed 2026-09-29,
/// all 14 names), so the page looks as it does in the app on the Mac that exported it.
enum SystemColorResolver {
    static let colors: [String: NSColor] = [
        "text-background": .textBackgroundColor,
        "label": .labelColor,
        "secondary-label": .secondaryLabelColor,
        "quaternary-label": .quaternaryLabelColor,
        "separator": .separatorColor,
        "grid": .gridColor,
        "odd-alternating-content-background": NSColor.alternatingContentBackgroundColors[1],
        "find-highlight-background": .findHighlightColor,
        "blue": .systemBlue,
        "green": .systemGreen,
        "orange": .systemOrange,
        "red": .systemRed,
        "purple": .systemPurple,
        "gray": .systemGray,
    ]

    /// Every color, light and dark, as this Mac draws them now.
    static func current() -> SystemColors {
        SystemColors(light: values(in: .aqua), dark: values(in: .darkAqua))
    }

    private static func values(in appearance: NSAppearance.Name) -> [String: String] {
        var values: [String: String] = [:]
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            for (name, color) in colors {
                values[name] = css(color)
            }
        }
        return values
    }

    /// `rgb(r, g, b)`, or `rgba(r, g, b, a)` for a translucent color, in sRGB. A color with no sRGB
    /// form (a pattern) comes out black.
    static func css(_ color: NSColor) -> String {
        guard let color = color.usingColorSpace(.sRGB) else { return "rgb(0, 0, 0)" }
        let rgb = [color.redComponent, color.greenComponent, color.blueComponent]
            .map { String(Int((min(max($0, 0), 1) * 255).rounded())) }
            .joined(separator: ", ")
        return color.alphaComponent >= 1 ? "rgb(\(rgb))" : "rgba(\(rgb), \(String(format: "%.3f", color.alphaComponent)))"
    }
}
