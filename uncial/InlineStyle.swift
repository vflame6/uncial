import AppKit

extension NSAttributedString.Key {
    /// Paragraph decoration drawn by `InlineLayoutManager`: "code", "quote:N" or "rule".
    static let blockDecoration = NSAttributedString.Key("uncialBlockDecoration")
    /// A task box `[ ]`/`[x]` drawn by `InlineLayoutManager`: "unchecked" or "checked".
    static let taskBox = NSAttributedString.Key("uncialTaskBox")
    /// An `InlineImage` drawn by `InlineLayoutManager` in the paragraph's reserved spacing.
    static let inlineImage = NSAttributedString.Key("uncialInlineImage")
}

/// A loaded image and the size it is drawn at under its paragraph.
final class InlineImage: NSObject {
    let image: NSImage
    let size: NSSize

    init(image: NSImage, size: NSSize) {
        self.image = image
        self.size = size
    }
}

/// Attributes for the inline presentation: headings sized, markers muted, code on a background,
/// list items hanging, quotes indented behind a border, links in the accent color. Attribute-only,
/// so undo never sees it; the fonts stay SF Mono.
struct InlineStyle {
    static let headingSizes: [CGFloat] = [22, 19, 16, 14, 13, 13]
    static let quoteIndent: CGFloat = 16
    static let codeIndent: CGFloat = 12
    static let maximumImageHeight: CGFloat = 480
    static let imageGap: CGFloat = 8

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

    /// `storage` must already carry the base attributes for its whole text. `images` loads an
    /// image token's destination (nil keeps it as source); `textWidth` is the room for text, which
    /// bounds the drawn size. Returns the locations of the image tokens that got an image.
    @discardableResult
    func apply(_ tokens: [MarkdownHighlighter.Token], to storage: NSTextStorage, images: (String) -> NSImage? = { _ in nil }, textWidth: CGFloat = .greatestFiniteMagnitude) -> Set<Int> {
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
            case .listItem(_, let box):
                storage.addAttribute(.foregroundColor, value: style.accent, range: token.range)
                if let box {
                    let checked = text.character(at: box.location + 1) != 0x20
                    storage.addAttribute(.taskBox, value: checked ? "checked" : "unchecked", range: box)
                }
                // The box's brackets are hidden, so the visible prefix is two characters shorter.
                let hanging = NSMutableParagraphStyle()
                hanging.headIndent = characterWidth * CGFloat(token.range.length - (box == nil ? 0 : 2))
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
        return reserveImages(tokens, in: storage, images: images, textWidth: textWidth)
    }

    /// The first image of a paragraph that loads gets drawn under it: the paragraph's spacing
    /// grows by the fitted height plus a gap, and the picture rides along as an attribute.
    private func reserveImages(_ tokens: [MarkdownHighlighter.Token], in storage: NSTextStorage, images: (String) -> NSImage?, textWidth: CGFloat) -> Set<Int> {
        let text = storage.string as NSString
        var resolved: Set<Int> = []
        var decorated: Set<Int> = []
        for token in tokens {
            guard case .image(let destination) = token.kind else { continue }
            let paragraph = text.paragraphRange(for: token.range)
            guard !decorated.contains(paragraph.location), let image = images(destination),
                  image.size.width > 0, image.size.height > 0 else { continue }
            let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let available = max(40, textWidth - (existing?.headIndent ?? 0))
            let scale = min(1, available / image.size.width, Self.maximumImageHeight / image.size.height)
            let size = NSSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
            let spaced = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            spaced.paragraphSpacing = size.height + Self.imageGap
            storage.addAttributes([.paragraphStyle: spaced, .inlineImage: InlineImage(image: image, size: size)], range: paragraph)
            decorated.insert(paragraph.location)
            resolved.insert(token.range.location)
        }
        return resolved
    }

    private func addTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? style.regular
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }
}
