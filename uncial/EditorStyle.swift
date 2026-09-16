import AppKit
import UncialCore

/// Fonts and colors for the source editor, from the theme's palette or the system colors.
struct EditorStyle {
    let background: NSColor
    let foreground: NSColor
    let accent: NSColor
    let muted: NSColor
    let code: NSColor
    let regular: NSFont
    let bold: NSFont
    let italic: NSFont

    init(palette: EditorPalette?, isDark: Bool) {
        let colors = palette.map { isDark ? $0.dark : $0.light }
        background = colors.map { NSColor(rgb: $0.background) } ?? .textBackgroundColor
        foreground = colors.map { NSColor(rgb: $0.foreground) } ?? .textColor
        accent = colors.map { NSColor(rgb: $0.accent) } ?? .linkColor
        muted = colors.map { NSColor(rgb: $0.muted) } ?? .secondaryLabelColor
        code = colors.map { NSColor(rgb: $0.code) } ?? .systemTeal
        regular = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        bold = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        italic = NSFontManager.shared.convert(regular, toHaveTrait: .italicFontMask)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: regular, .foregroundColor: foreground]
    }

    func attributes(for kind: MarkdownHighlighter.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .heading: [.font: bold, .foregroundColor: accent]
        case .strong: [.font: bold]
        case .emphasis: [.font: italic]
        case .strikethrough: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .inlineCode, .codeBlock, .math: [.foregroundColor: code]
        case .link, .listMarker: [.foregroundColor: accent]
        case .url, .quote, .rule, .frontMatter, .table, .html: [.foregroundColor: muted]
        }
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
