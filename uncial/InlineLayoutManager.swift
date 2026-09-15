import AppKit

/// Draws the inline presentation's block decorations behind the text: a rounded background
/// across a fenced code block, a left border per quote level, a rule line. Driven by the
/// `.blockDecoration` paragraph attribute, so it needs no NSTextBlock and adds no padding.
final class InlineLayoutManager: NSLayoutManager {
    static let cornerRadius: CGFloat = 6
    static let borderWidth: CGFloat = 3

    var codeBackground: NSColor = .clear
    var lineColor: NSColor = .clear

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        // Per fragment, keyed by the paragraph of its first character: hidden (zero-width) markers
        // at a paragraph start are laid out at the end of the previous line's fragment, so the
        // glyph range of a paragraph is not a reliable way to find its fragments.
        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, _, fragmentGlyphs, _ in
            let fragment = self.characterRange(forGlyphRange: fragmentGlyphs, actualGlyphRange: nil)
            guard fragment.location < text.length,
                  let decoration = storage.attribute(.blockDecoration, at: fragment.location, effectiveRange: nil) as? String else { return }
            let paragraph = text.paragraphRange(for: NSRange(location: fragment.location, length: 0))
            let box = rect.offsetBy(dx: origin.x, dy: origin.y)
            switch decoration {
            case "code":
                let before = paragraph.location > 0 ? storage.attribute(.blockDecoration, at: paragraph.location - 1, effectiveRange: nil) as? String : nil
                let after = NSMaxRange(paragraph) < text.length ? storage.attribute(.blockDecoration, at: NSMaxRange(paragraph), effectiveRange: nil) as? String : nil
                let isFirst = before != "code" && self.startsParagraph(fragmentGlyphs, paragraph: paragraph)
                let isLast = after != "code" && NSMaxRange(fragment) >= NSMaxRange(paragraph)
                self.fillCode(box, roundTop: isFirst, roundBottom: isLast)
            case "rule":
                self.lineColor.setFill()
                NSRect(x: box.minX, y: floor(box.midY), width: box.width, height: 1).fill()
            default:
                guard decoration.hasPrefix("quote:"), let depth = Int(decoration.dropFirst(6)) else { return }
                self.lineColor.setFill()
                for level in 0..<depth {
                    NSRect(x: box.minX + InlineStyle.quoteIndent * CGFloat(level) + 2, y: box.minY, width: Self.borderWidth, height: box.height).fill()
                }
            }
        }
    }

    /// Whether the fragment is its paragraph's first: the previous fragment starts before the paragraph.
    private func startsParagraph(_ fragmentGlyphs: NSRange, paragraph: NSRange) -> Bool {
        guard fragmentGlyphs.location > 0 else { return true }
        var previousGlyphs = NSRange()
        _ = lineFragmentRect(forGlyphAt: fragmentGlyphs.location - 1, effectiveRange: &previousGlyphs)
        return characterRange(forGlyphRange: previousGlyphs, actualGlyphRange: nil).location < paragraph.location
    }

    /// One rounded rectangle per block, painted piecewise: each fragment clips a rectangle that is
    /// extended past the edges that must stay square. The text view's coordinates are flipped, so
    /// "top" is `minY`.
    private func fillCode(_ box: NSRect, roundTop: Bool, roundBottom: Bool) {
        let radius = Self.cornerRadius
        var extended = box
        if !roundTop {
            extended.origin.y -= radius
            extended.size.height += radius
        }
        if !roundBottom {
            extended.size.height += radius
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: box).addClip()
        codeBackground.setFill()
        NSBezierPath(roundedRect: extended, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
