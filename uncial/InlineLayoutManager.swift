import AppKit
import UncialCore

/// Draws the inline presentation's block decorations behind the text: a rounded background
/// across a fenced code block, a left border per quote level, a rule line, a divider under an h1
/// or h2, a tinted box per callout level with the callout's icon and default title. Driven by the
/// `.blockDecoration` paragraph attribute (and `.calloutTitle`), so it needs no NSTextBlock and adds no
/// padding. Also draws the pictures: images under their paragraph, formulas on their anchor glyph;
/// and a tinted band behind the revealed lines (the caret's, in the source look).
final class InlineLayoutManager: NSLayoutManager {
    static let cornerRadius: CGFloat = 6
    static let borderWidth: CGFloat = 3

    var codeBackground: NSColor = .clear
    var lineColor: NSColor = .clear
    var accent: NSColor = .clear
    /// The divider under a rendered h1 or h2.
    var separatorColor: NSColor = .clear
    /// The callout colors per role: the box is the color at 10%, icon and title the color itself.
    var calloutColors: [Callouts.Role: NSColor] = [:]
    var calloutTitleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    var calloutIconSize: CGFloat = InlineStyle.calloutIconSize
    /// The paragraphs whose markers are shown; a rule there gives way to its raw text.
    var revealed = NSRange(location: 0, length: 0)
    /// The band behind the revealed lines, and its room above and below their text.
    var revealBackground: NSColor = .clear
    var revealPadding: CGFloat = InlineStyle.revealPadding

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // First, so the selection and the text's own backgrounds stay on top of it.
        drawRevealBand(at: origin)
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
            self.drawCalloutTitle(in: fragment, fragmentGlyphs: fragmentGlyphs, lineRect: box, container: container, storage: storage, text: text)
            self.drawTaskBoxes(in: fragment, lineRect: box, container: container, origin: origin, storage: storage)
            self.drawImage(in: fragment, lineRect: box, container: container, storage: storage, text: text)
        }
    }

    /// A formula's picture sits on its anchor glyph, a whitespace box of the picture's size laid out by
    /// `ThemedTextView`, with the picture's baseline on the text's.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.mathPicture, in: characters, options: []) { value, range, _ in
            guard let picture = value as? MathPicture else { return }
            let glyph = glyphIndexForCharacter(at: range.location)
            guard propertyForGlyph(at: glyph) == .controlCharacter else { return }
            let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let position = location(forGlyphAt: glyph)
            let target = NSRect(x: origin.x + fragment.minX + position.x, y: origin.y + fragment.minY + position.y - picture.baseline,
                                width: picture.size.width, height: picture.size.height)
            picture.image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// A rounded band across the text column behind the revealed lines, from `revealPadding` above the
    /// first line's text to as far below the last line's. The text is found from the used rects, which
    /// hold the line (`ThemedTextView` puts the band's room outside them): the font's line box sits
    /// below half the extra line height, the paragraph style's line spacing being the other half.
    /// A newline glyph's location is no baseline (an empty line's reads 4.75 pt low; probed 2026-09-26).
    private func drawRevealBand(at origin: NSPoint) {
        guard revealed.length > 0, revealBackground.alphaComponent > 0, let storage = textStorage, NSMaxRange(revealed) <= storage.length,
              let font = storage.attribute(.font, at: revealed.location, effectiveRange: nil) as? NSFont else { return }
        let glyphs = glyphRange(forCharacterRange: revealed, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        let half = (storage.attribute(.paragraphStyle, at: revealed.location, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0
        let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let first = lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let last = lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
        let top = first.minY + half - revealPadding
        let bottom = last.minY + half + defaultLineHeight(for: font) + revealPadding
        let band = NSRect(x: origin.x + fragment.minX, y: origin.y + top, width: fragment.width, height: bottom - top)
        revealBackground.setFill()
        NSBezierPath(roundedRect: band, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
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
            fill(box, with: codeBackground, roundTop: isFirst, roundBottom: isLast)
        case "rule":
            guard !NSLocationInRange(paragraph.location, revealed) else { return }
            lineColor.setFill()
            NSRect(x: box.minX, y: floor(box.midY), width: box.width, height: 1).fill()
        case "heading":
            // Under the paragraph's last fragment, whose rect includes the paragraph spacing above the line.
            guard NSMaxRange(fragment) >= NSMaxRange(paragraph) else { return }
            separatorColor.setFill()
            NSRect(x: box.minX, y: box.maxY - 1, width: box.width, height: 1).fill()
        default:
            if decoration.hasPrefix("quote:"), let depth = Int(decoration.dropFirst(6)) {
                lineColor.setFill()
                for level in 0..<depth {
                    NSRect(x: box.minX + InlineStyle.quoteIndent * CGFloat(level) + 2, y: box.minY, width: Self.borderWidth, height: box.height).fill()
                }
                return
            }
            // A stack, one entry per quote level: a callout's box from that level's indent to the right
            // edge, rounded where the neighboring paragraphs are not in the same callout, or a quote's bar.
            let before = paragraph.location > 0 ? storage.attribute(.blockDecoration, at: paragraph.location - 1, effectiveRange: nil) as? String : nil
            let after = NSMaxRange(paragraph) < text.length ? storage.attribute(.blockDecoration, at: NSMaxRange(paragraph), effectiveRange: nil) as? String : nil
            for (level, entry) in decoration.split(separator: "|").map(String.init).enumerated() {
                let left = box.minX + InlineStyle.quoteIndent * CGFloat(level)
                if entry.hasPrefix("callout:") {
                    guard let color = calloutColors[Callouts.role(for: String(entry.dropFirst(8)))] else { continue }
                    let isFirst = Self.entry(at: level, in: before) != entry && startsParagraph(fragmentGlyphs, paragraph: paragraph)
                    let isLast = Self.entry(at: level, in: after) != entry && NSMaxRange(fragment) >= NSMaxRange(paragraph)
                    fill(NSRect(x: left, y: box.minY, width: box.maxX - left, height: box.height), with: color.withAlphaComponent(0.1), roundTop: isFirst, roundBottom: isLast)
                } else {
                    lineColor.setFill()
                    NSRect(x: left + 2, y: box.minY, width: Self.borderWidth, height: box.height).fill()
                }
            }
        }
    }

    /// The entry at a quote level of a decoration: `quote` inside a `quote:N`, the level's entry of a stack, nil otherwise.
    private static func entry(at level: Int, in decoration: String?) -> String? {
        guard let decoration else { return nil }
        if decoration.hasPrefix("quote:") {
            return level < (Int(decoration.dropFirst(6)) ?? 0) ? "quote" : nil
        }
        let levels = decoration.split(separator: "|")
        return level < levels.count ? String(levels[level]) : nil
    }

    /// A callout's icon at the content indent of its level, centered on the title's capitals, and,
    /// when the line names no title, the default title after it; only while the markers are hidden.
    private func drawCalloutTitle(in fragment: NSRange, fragmentGlyphs: NSRange, lineRect: NSRect, container: NSTextContainer, storage: NSTextStorage, text: NSString) {
        guard let title = storage.attribute(.calloutTitle, at: fragment.location, effectiveRange: nil) as? CalloutTitle,
              !NSLocationInRange(fragment.location, revealed),
              let color = calloutColors[Callouts.role(for: title.type)] else { return }
        let paragraph = text.paragraphRange(for: NSRange(location: fragment.location, length: 0))
        guard startsParagraph(fragmentGlyphs, paragraph: paragraph) else { return }
        let baseline = location(forGlyphAt: fragmentGlyphs.location).y
        let x = lineRect.minX + container.lineFragmentPadding + InlineStyle.quoteIndent * CGFloat(title.depth)
        let size = calloutIconSize
        let iconRect = NSRect(x: x, y: lineRect.minY + baseline - calloutTitleFont.capHeight / 2 - size / 2, width: size, height: size)
        if let icon = CalloutIcons.image(for: title.type, color: color, size: size) {
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if let defaultTitle = title.defaultTitle {
            let string = NSAttributedString(string: defaultTitle, attributes: [.font: calloutTitleFont, .foregroundColor: color])
            string.draw(at: NSPoint(x: x + size + InlineStyle.calloutIconGap, y: lineRect.minY + baseline - calloutTitleFont.ascender))
        }
    }

    /// A rounded square centered in the room of the box's middle character (kerned out to
    /// `InlineStyle.taskBoxWidth`), drawn only while the brackets are hidden (a revealed line shows
    /// the raw `[ ]`). The room ends where the glyph after the hidden `]` starts.
    private func drawTaskBoxes(in fragment: NSRange, lineRect: NSRect, container: NSTextContainer, origin: NSPoint, storage: NSTextStorage) {
        storage.enumerateAttribute(.taskBox, in: fragment, options: []) { value, range, _ in
            guard let state = value as? String, range.length == 3,
                  propertyForGlyph(at: glyphIndexForCharacter(at: range.location)) == .null else { return }
            let middle = glyphIndexForCharacter(at: range.location + 1)
            var fragmentGlyphs = NSRange()
            let fragmentRect = lineFragmentRect(forGlyphAt: middle, effectiveRange: &fragmentGlyphs)
            let start = location(forGlyphAt: middle).x
            let after = middle + 2
            let end = after < NSMaxRange(fragmentGlyphs) ? location(forGlyphAt: after).x : start + InlineStyle.taskBoxWidth
            let cell = NSRect(x: origin.x + fragmentRect.minX + start, y: lineRect.minY, width: max(end - start, 1), height: lineRect.height)
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
    private func fill(_ box: NSRect, with color: NSColor, roundTop: Bool, roundBottom: Bool) {
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
        color.setFill()
        NSBezierPath(roundedRect: extended, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
