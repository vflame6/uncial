import AppKit
import UncialCore

/// Fonts and colors for the editor. The source look is SF Mono with the theme's palette (or the
/// system colors); the rendered look, which Live Preview gives every line but the caret's, follows
/// the theme's page: the system font at the page's body and heading sizes and line heights.
struct EditorStyle {
    let background: NSColor
    let foreground: NSColor
    let accent: NSColor
    let muted: NSColor
    let code: NSColor
    /// The theme's colors for highlighted code, per `CodeHighlighter.Scope`.
    let syntax: SyntaxPalette.Colors
    let regular: NSFont
    let bold: NSFont
    let italic: NSFont
    /// Body size in points of the mono font; everything else scales from it (13 is the system size).
    let size: CGFloat
    /// Whether the colors are the dark variant.
    let isDark: Bool
    /// The page's type scale the rendered look follows.
    let typography: PageTypography
    /// The rendered look's text font: the system font at the theme's body size, scaled like the mono font.
    let body: NSFont

    init(theme: Theme, isDark: Bool, size: CGFloat = 13) {
        self.size = size
        self.isDark = isDark
        typography = theme.typography
        let syntaxPalette = theme.syntaxPalette
        syntax = isDark ? syntaxPalette.dark : syntaxPalette.light
        let colors = theme.editorPalette.map { isDark ? $0.dark : $0.light }
        background = colors.map { NSColor(rgb: $0.background) } ?? .textBackgroundColor
        foreground = colors.map { NSColor(rgb: $0.foreground) } ?? .textColor
        accent = colors.map { NSColor(rgb: $0.accent) } ?? .linkColor
        muted = colors.map { NSColor(rgb: $0.muted) } ?? .secondaryLabelColor
        code = colors.map { NSColor(rgb: $0.code) } ?? .systemTeal
        regular = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        bold = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        italic = NSFontManager.shared.convert(regular, toHaveTrait: .italicFontMask)
        body = NSFont.systemFont(ofSize: CGFloat(typography.bodySize) * size / 13)
    }

    var scale: CGFloat { size / 13 }

    func color(for scope: CodeHighlighter.Scope) -> NSColor {
        NSColor(rgb: syntax.color(for: scope))
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

    // MARK: Rendered look

    /// The rendered look's base: body font, text color, the page's line height.
    var renderedAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: foreground, .paragraphStyle: paragraphStyle(for: body, lineHeight: typography.lineHeight).copy() as! NSParagraphStyle]
    }

    /// A heading in the rendered look: the theme's size, semibold, bold for h1 and h2 where the page has them bold.
    func heading(level: Int) -> NSFont {
        let index = max(1, min(level, 6)) - 1
        let weight: NSFont.Weight = typography.boldTopHeadings && index < 2 ? .bold : .semibold
        return NSFont.systemFont(ofSize: CGFloat(typography.headingSizes[index]) * scale, weight: weight)
    }

    /// Code inside rendered text: the mono font at 85% of the font it sits in, like the page's `code`.
    func codeFont(within font: NSFont) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: font.pointSize * CGFloat(PageTypography.codeScale), weight: .regular)
    }

    /// `lineHeightMultiple` that gives `font` a line height of `lineHeight` times its size, as CSS
    /// would: the factor applies to the layout manager's default line height for the font.
    func lineHeightMultiple(for font: NSFont, lineHeight: Double) -> CGFloat {
        let natural = Self.measure.defaultLineHeight(for: font)
        return natural > 0 ? font.pointSize * CGFloat(lineHeight) / natural : 1
    }

    private static let measure = NSLayoutManager()

    func paragraphStyle(for font: NSFont, lineHeight: Double) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple(for: font, lineHeight: lineHeight)
        return style
    }

    /// A superscript (or subscript) inside rendered text: 70% of the font it sits in, raised (or lowered).
    func scriptAttributes(within font: NSFont, lowered: Bool = false) -> [NSAttributedString.Key: Any] {
        let size = (font.pointSize * 0.7).rounded()
        let offset = (font.pointSize * (lowered ? -0.15 : 0.3)).rounded()
        return [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .baselineOffset: offset]
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
