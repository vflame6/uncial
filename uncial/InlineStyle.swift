import AppKit

extension NSAttributedString.Key {
    /// Paragraph decoration drawn by `InlineLayoutManager`: "code", "quote:N" or "rule".
    static let blockDecoration = NSAttributedString.Key("uncialBlockDecoration")
}

/// Attributes for the inline presentation: headings sized, markers muted, code on a background,
/// list items hanging, quotes indented behind a border, links in the accent color. Attribute-only,
/// so undo never sees it; the fonts stay SF Mono.
struct InlineStyle {
    static let headingSizes: [CGFloat] = [22, 19, 16, 14, 13, 13]
    static let quoteIndent: CGFloat = 16
    static let codeIndent: CGFloat = 12

    let style: EditorStyle
    let characterWidth: CGFloat

    var codeBackground: NSColor { style.foreground.withAlphaComponent(0.06) }

    init(style: EditorStyle) {
        self.style = style
        characterWidth = Self.advance(of: "0", in: style.regular)
    }

    /// The advance of one character in a font, straight from CoreText.
    static func advance(of character: Character, in font: NSFont) -> CGFloat {
        var characters = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font as CTFont, &characters, &glyphs, characters.count) else {
            return font.maximumAdvancement.width
        }
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        return CTFontGetAdvancesForGlyphs(font as CTFont, .horizontal, &glyphs, &advances, glyphs.count)
    }

    func headingFont(level: Int) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: Self.headingSizes[max(1, min(level, 6)) - 1], weight: .bold)
    }

    /// `storage` must already carry the base attributes for its whole text.
    func apply(_ tokens: [MarkdownHighlighter.Token], to storage: NSTextStorage) {
        let text = storage.string as NSString
        for token in tokens {
            let paragraph = text.paragraphRange(for: token.range)
            switch token.kind {
            case .heading(let level):
                storage.addAttributes([.font: headingFont(level: level), .foregroundColor: level == 6 ? style.muted : style.foreground], range: token.range)
            case .strong:
                addTrait(.boldFontMask, to: storage, in: token.range)
            case .emphasis:
                addTrait(.italicFontMask, to: storage, in: token.range)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: token.range)
            case .inlineCode:
                storage.addAttributes([.foregroundColor: style.code, .backgroundColor: codeBackground], range: token.range)
            case .link(let destination), .autolink(let destination):
                storage.addAttributes([.foregroundColor: style.accent, .link: destination], range: token.range)
            case .image:
                storage.addAttribute(.foregroundColor, value: style.accent, range: token.range)
            case .listItem:
                storage.addAttribute(.foregroundColor, value: style.accent, range: token.range)
                let hanging = NSMutableParagraphStyle()
                hanging.headIndent = characterWidth * CGFloat(token.range.length)
                storage.addAttribute(.paragraphStyle, value: hanging, range: paragraph)
            case .quote(let depth):
                let indented = NSMutableParagraphStyle()
                indented.firstLineHeadIndent = Self.quoteIndent * CGFloat(depth)
                indented.headIndent = indented.firstLineHeadIndent
                storage.addAttributes([.paragraphStyle: indented, .blockDecoration: "quote:\(depth)", .foregroundColor: style.muted], range: paragraph)
            case .rule:
                storage.addAttributes([.blockDecoration: "rule", .foregroundColor: style.muted], range: paragraph)
            case .fence, .code:
                let inset = NSMutableParagraphStyle()
                inset.firstLineHeadIndent = Self.codeIndent
                inset.headIndent = Self.codeIndent
                storage.addAttributes([.paragraphStyle: inset, .blockDecoration: "code"], range: paragraph)
                storage.addAttribute(.foregroundColor, value: token.kind == .fence ? style.muted : style.code, range: token.range)
            case .frontMatter:
                storage.addAttribute(.foregroundColor, value: style.muted, range: token.range)
            }
            for marker in token.markers {
                storage.addAttribute(.foregroundColor, value: style.muted, range: marker)
            }
        }
    }

    private func addTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? style.regular
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }
}
