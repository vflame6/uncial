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
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.blockDecoration, in: characters, options: []) { value, range, _ in
            guard let decoration = value as? String else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, fragmentGlyphs, _ in
                let box = rect.offsetBy(dx: origin.x, dy: origin.y)
                switch decoration {
                case "code":
                    let fragment = self.characterRange(forGlyphRange: fragmentGlyphs, actualGlyphRange: nil)
                    let paragraph = text.paragraphRange(for: fragment)
                    let before = paragraph.location > 0 ? storage.attribute(.blockDecoration, at: paragraph.location - 1, effectiveRange: nil) as? String : nil
                    let after = NSMaxRange(paragraph) < text.length ? storage.attribute(.blockDecoration, at: NSMaxRange(paragraph), effectiveRange: nil) as? String : nil
                    let isFirst = before != "code" && fragment.location == paragraph.location
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
