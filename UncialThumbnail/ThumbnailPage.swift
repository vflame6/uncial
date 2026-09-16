import AppKit
import CoreGraphics
import UncialCore

/// A document's outline typeset like the rendered page and drawn at thumbnail size: a light page
/// with the theme's colors, system fonts scaled to the page width, bullets, quote bars, code tints,
/// rules and table rows. TextKit 1 lays the text out; the decorations are painted per block from
/// its line fragments. Everything is built per call, so drawing may happen on any thread.
struct ThumbnailPage {
    struct Palette {
        var background: NSColor
        var foreground: NSColor
        var accent: NSColor
        var muted: NSColor

        /// The theme's light colors; the macOS theme uses the system's, resolved for the Aqua appearance.
        static func light(for theme: Theme) -> Palette {
            guard let colors = theme.editorPalette?.light else {
                return Palette(background: .textBackgroundColor, foreground: .labelColor, accent: .controlAccentColor, muted: .secondaryLabelColor)
            }
            return Palette(background: NSColor(rgb: colors.background), foreground: NSColor(rgb: colors.foreground),
                           accent: NSColor(rgb: colors.accent), muted: NSColor(rgb: colors.muted))
        }

        var codeBackground: NSColor { foreground.withAlphaComponent(0.07) }
        var border: NSColor { foreground.withAlphaComponent(0.2) }
    }

    /// Width to height of the page, like a sheet of paper.
    static let aspectRatio: CGFloat = 0.75

    let blocks: [MarkdownOutline.Block]
    let palette: Palette

    /// A portrait page as large as `maximum` allows, never smaller than `minimum`.
    static func pageSize(fitting maximum: CGSize, atLeast minimum: CGSize = .zero) -> CGSize {
        var width = min(maximum.width, maximum.height * aspectRatio)
        var height = width / aspectRatio
        width = max(width, minimum.width)
        height = max(height, minimum.height)
        return CGSize(width: width.rounded(.down), height: height.rounded(.down))
    }

    /// Fills `size` points with the page. `context` is a Quartz context of `size × scale` pixels
    /// with the origin at the bottom and an identity transform, which is what Quick Look hands a
    /// thumbnail reply (it does not apply the request's scale); the page flips it and draws top-down.
    func draw(in size: CGSize, scale: CGFloat = 1, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let appearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            palette.background.setFill()
            CGRect(origin: .zero, size: size).fill()
            let inset = (size.width / 14).rounded()
            let content = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
            let layout = Layout(blocks: blocks, palette: palette, width: content.width, bodySize: (size.width / 32).rounded())
            context.clip(to: content)
            layout.draw(at: content.origin, height: content.height)
        }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    /// The typeset text plus the character range of every block, laid out for one width.
    final class Layout {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container: NSTextContainer
        let palette: Palette
        let bodySize: CGFloat
        let width: CGFloat
        private(set) var ranges: [(block: MarkdownOutline.Block, range: NSRange)] = []

        init(blocks: [MarkdownOutline.Block], palette: Palette, width: CGFloat, bodySize: CGFloat) {
            self.palette = palette
            self.bodySize = max(bodySize, 3)
            self.width = width
            container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)
            for block in blocks {
                let text = attributedString(for: block)
                let range = NSRange(location: storage.length, length: text.length)
                storage.append(text)
                ranges.append((block, range))
            }
        }

        /// Fonts scale with the page: body at `bodySize`, headings up to twice that.
        func font(for block: MarkdownOutline.Block, run: MarkdownOutline.Run) -> NSFont {
            var size = bodySize
            var weight: NSFont.Weight = .regular
            if case .heading(let level) = block.kind {
                size = bodySize * [2.0, 1.6, 1.3, 1.15, 1, 1][min(max(level, 1), 6) - 1]
                weight = level <= 2 ? .bold : .semibold
            }
            if run.isStrong { weight = .bold }
            if case .tableRow(_, let isHeader) = block.kind, isHeader { weight = .semibold }
            var font = run.isCode || block.kind == .code
                ? NSFont.monospacedSystemFont(ofSize: size * 0.88, weight: weight)
                : NSFont.systemFont(ofSize: size, weight: weight)
            if run.isEmphasis || run.isImage, let italic = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: font.pointSize) {
                font = italic
            }
            return font
        }

        func attributedString(for block: MarkdownOutline.Block) -> NSAttributedString {
            let text = NSMutableAttributedString()
            let indent = CGFloat(block.quoteDepth) * bodySize * 1.2 + CGFloat(max(block.listDepth - 1, 0)) * bodySize * 1.5
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.2
            paragraph.paragraphSpacing = bodySize * 0.7
            paragraph.firstLineHeadIndent = indent
            paragraph.headIndent = indent
            switch block.kind {
            case .heading(let level):
                paragraph.paragraphSpacingBefore = bodySize * (level <= 2 ? 0.8 : 0.5)
            case .listItem(let marker):
                let markerWidth = bodySize * 1.5
                paragraph.firstLineHeadIndent = indent
                paragraph.headIndent = indent + markerWidth
                paragraph.paragraphSpacing = bodySize * 0.2
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]
                text.append(NSAttributedString(string: marker + "\t", attributes: [
                    .font: NSFont.systemFont(ofSize: bodySize, weight: .regular),
                    .foregroundColor: marker == "•" ? palette.accent : palette.muted,
                ]))
            case .code:
                paragraph.firstLineHeadIndent = indent + bodySize
                paragraph.headIndent = indent + bodySize
                paragraph.paragraphSpacingBefore = bodySize * 0.6
                paragraph.paragraphSpacing = bodySize * 1.2
            case .rule:
                paragraph.paragraphSpacingBefore = bodySize * 0.3
                paragraph.paragraphSpacing = bodySize * 0.3
                text.append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: bodySize)]))
            case .tableRow(let cells, _):
                paragraph.paragraphSpacing = bodySize * 0.25
                let column = width / CGFloat(max(cells.count, 1))
                paragraph.tabStops = (1..<max(cells.count, 1)).map { NSTextTab(textAlignment: .left, location: indent + column * CGFloat($0)) }
                for (index, cell) in cells.enumerated() {
                    if index > 0 { text.append(NSAttributedString(string: "\t", attributes: [.font: NSFont.systemFont(ofSize: bodySize)])) }
                    for run in cell {
                        text.append(NSAttributedString(string: run.text.replacingOccurrences(of: "\n", with: " "), attributes: attributes(for: run, in: block)))
                    }
                }
            case .paragraph:
                break
            }
            for run in block.runs {
                // Line breaks inside a block stay inside its paragraph, so spacing and the
                // decorations apply to the block as a whole.
                var content = run.text
                if block.kind == .code, content.hasSuffix("\n") { content.removeLast() }
                content = content.replacingOccurrences(of: "\n", with: "\u{2028}")
                text.append(NSAttributedString(string: content, attributes: attributes(for: run, in: block)))
            }
            text.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: bodySize)]))
            text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
            return text
        }

        func attributes(for run: MarkdownOutline.Run, in block: MarkdownOutline.Block) -> [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [.font: font(for: block, run: run)]
            var color = palette.foreground
            if block.quoteDepth > 0 || run.isImage { color = palette.muted }
            if case .heading(let level) = block.kind, level == 6 { color = palette.muted }
            if run.isLink { color = palette.accent }
            attributes[.foregroundColor] = color
            if run.isStrikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if run.isCode, block.kind != .code { attributes[.backgroundColor] = palette.codeBackground }
            return attributes
        }

        /// Paints the decorations, then the text, with the page's top-left at `origin`; nothing
        /// below `height` is drawn.
        func draw(at origin: CGPoint, height: CGFloat) {
            let glyphRange = layoutManager.glyphRange(for: container)
            layoutManager.ensureLayout(for: container)
            for (block, range) in ranges {
                let rect = self.rect(of: range)
                guard rect.minY < height else { break }
                let indent = CGFloat(block.quoteDepth) * bodySize * 1.2 + CGFloat(max(block.listDepth - 1, 0)) * bodySize * 1.5
                let line = max(1, bodySize / 12)
                switch block.kind {
                case .code:
                    let box = CGRect(x: origin.x + indent, y: origin.y + rect.minY - bodySize * 0.4, width: width - indent, height: rect.height + bodySize * 0.8)
                    palette.codeBackground.setFill()
                    NSBezierPath(roundedRect: box, xRadius: bodySize * 0.4, yRadius: bodySize * 0.4).fill()
                case .rule:
                    palette.border.setFill()
                    CGRect(x: origin.x + indent, y: origin.y + rect.midY, width: width - indent, height: line).fill()
                case .heading(let level) where level <= 2:
                    palette.border.setFill()
                    CGRect(x: origin.x + indent, y: origin.y + rect.maxY + bodySize * 0.15, width: width - indent, height: line).fill()
                case .tableRow(_, let isHeader):
                    (isHeader ? palette.border : palette.codeBackground).setFill()
                    CGRect(x: origin.x + indent, y: origin.y + rect.maxY + bodySize * 0.1, width: width - indent, height: line).fill()
                default:
                    break
                }
                if block.quoteDepth > 0 {
                    palette.border.setFill()
                    for level in 0..<block.quoteDepth {
                        let x = origin.x + CGFloat(level) * bodySize * 1.2
                        CGRect(x: x, y: origin.y + rect.minY, width: max(1.5, bodySize / 5), height: rect.height).fill()
                    }
                }
            }
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        }

        /// The text of `range`: the union of its used line fragments, without paragraph spacing.
        /// (`boundingRect(forGlyphRange:in:)` misreports ranges that span several lines.)
        func rect(of range: NSRange) -> CGRect {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var union = CGRect.null
            var index = glyphs.location
            while index < NSMaxRange(glyphs) {
                var fragment = NSRange()
                union = union.union(layoutManager.lineFragmentUsedRect(forGlyphAt: index, effectiveRange: &fragment))
                index = max(NSMaxRange(fragment), index + 1)
            }
            return union.isNull ? .zero : union
        }
    }
}

extension NSColor {
    /// A color from 0xRRGGBB in sRGB.
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
