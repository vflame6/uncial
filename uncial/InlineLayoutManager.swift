import AppKit

/// Draws the inline presentation's block decorations behind the text: a rounded background
/// across a fenced code block, a left border per quote level, a rule line. Driven by the
/// `.blockDecoration` paragraph attribute, so it needs no NSTextBlock and adds no padding.
final class InlineLayoutManager: NSLayoutManager {
    static let cornerRadius: CGFloat = 6
    static let borderWidth: CGFloat = 3

    var codeBackground: NSColor = .clear
    var lineColor: NSColor = .clear
    var accent: NSColor = .clear
    /// The paragraphs whose markers are shown; a rule there gives way to its raw text.
    var revealed = NSRange(location: 0, length: 0)

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        // Per fragment, keyed by the paragraph of its first character: hidden (zero-width) markers
        // at a paragraph start are laid out at the end of the previous line's fragment, so the
        // glyph range of a paragraph is not a reliable way to find its fragments.
        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, container, fragmentGlyphs, _ in
            let fragment = self.characterRange(forGlyphRange: fragmentGlyphs, actualGlyphRange: nil)
            guard fragment.location < text.length else { return }
            let box = rect.offsetBy(dx: origin.x, dy: origin.y)
            if let decoration = storage.attribute(.blockDecoration, at: fragment.location, effectiveRange: nil) as? String {
                self.draw(decoration, in: box, fragment: fragment, fragmentGlyphs: fragmentGlyphs, storage: storage, text: text)
            }
            self.drawTaskBoxes(in: fragment, lineRect: box, container: container, origin: origin, storage: storage)
            self.drawImage(in: fragment, lineRect: box, container: container, storage: storage, text: text)
        }
    }

    /// The paragraph's image sits in the spacing below its last line fragment, left-aligned with the text.
    private func drawImage(in fragment: NSRange, lineRect: NSRect, container: NSTextContainer, storage: NSTextStorage, text: NSString) {
        guard let inline = storage.attribute(.inlineImage, at: fragment.location, effectiveRange: nil) as? InlineImage else { return }
        let paragraph = text.paragraphRange(for: NSRange(location: fragment.location, length: 0))
        guard NSMaxRange(fragment) >= NSMaxRange(paragraph) else { return }
        let indent = (storage.attribute(.paragraphStyle, at: fragment.location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
        let target = NSRect(x: lineRect.minX + container.lineFragmentPadding + indent,
                            y: lineRect.maxY - InlineStyle.imageGap / 2 - inline.size.height,
                            width: inline.size.width, height: inline.size.height)
        inline.image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func draw(_ decoration: String, in box: NSRect, fragment: NSRange, fragmentGlyphs: NSRange, storage: NSTextStorage, text: NSString) {
        let paragraph = text.paragraphRange(for: NSRange(location: fragment.location, length: 0))
        switch decoration {
        case "code":
            let before = paragraph.location > 0 ? storage.attribute(.blockDecoration, at: paragraph.location - 1, effectiveRange: nil) as? String : nil
            let after = NSMaxRange(paragraph) < text.length ? storage.attribute(.blockDecoration, at: NSMaxRange(paragraph), effectiveRange: nil) as? String : nil
            let isFirst = before != "code" && startsParagraph(fragmentGlyphs, paragraph: paragraph)
            let isLast = after != "code" && NSMaxRange(fragment) >= NSMaxRange(paragraph)
            fillCode(box, roundTop: isFirst, roundBottom: isLast)
        case "rule":
            guard !NSLocationInRange(paragraph.location, revealed) else { return }
            lineColor.setFill()
            NSRect(x: box.minX, y: floor(box.midY), width: box.width, height: 1).fill()
        default:
            guard decoration.hasPrefix("quote:"), let depth = Int(decoration.dropFirst(6)) else { return }
            lineColor.setFill()
            for level in 0..<depth {
                NSRect(x: box.minX + InlineStyle.quoteIndent * CGFloat(level) + 2, y: box.minY, width: Self.borderWidth, height: box.height).fill()
            }
        }
    }

    /// A rounded square centered on the box's middle character, drawn only while the brackets
    /// are hidden (a revealed line shows the raw `[ ]`).
    private func drawTaskBoxes(in fragment: NSRange, lineRect: NSRect, container: NSTextContainer, origin: NSPoint, storage: NSTextStorage) {
        storage.enumerateAttribute(.taskBox, in: fragment, options: []) { value, range, _ in
            guard let state = value as? String, range.length == 3,
                  propertyForGlyph(at: glyphIndexForCharacter(at: range.location)) == .null else { return }
            let middle = glyphIndexForCharacter(at: range.location + 1)
            let cell = boundingRect(forGlyphRange: NSRange(location: middle, length: 1), in: container).offsetBy(dx: origin.x, dy: origin.y)
            let side = min(14, lineRect.height - 5)
            let square = NSRect(x: cell.midX - side / 2, y: cell.midY - side / 2, width: side, height: side)
            let outline = NSBezierPath(roundedRect: square.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            if state == "checked" {
                accent.setFill()
                outline.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: square.minX + side * 0.22, y: square.minY + side * 0.5))
                check.line(to: NSPoint(x: square.minX + side * 0.42, y: square.minY + side * 0.72))
                check.line(to: NSPoint(x: square.minX + side * 0.78, y: square.minY + side * 0.3))
                check.lineWidth = 1.5
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.white.setStroke()
                check.stroke()
            } else {
                lineColor.setStroke()
                outline.lineWidth = 1
                outline.stroke()
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
