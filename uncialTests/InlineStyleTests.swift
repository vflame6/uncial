import AppKit
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite struct InlineStyleTests {
    private let style = EditorStyle(theme: .github, isDark: false)

    private func storage(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text, attributes: style.baseAttributes)
        InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: storage)
        return storage
    }

    private func font(_ storage: NSTextStorage, _ index: Int) -> NSFont {
        storage.attribute(.font, at: index, effectiveRange: nil) as! NSFont
    }

    private func color(_ storage: NSTextStorage, _ index: Int) -> NSColor? {
        storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    private func paragraph(_ storage: NSTextStorage, _ index: Int) -> NSParagraphStyle? {
        storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
    }

    private func decoration(_ storage: NSTextStorage, _ index: Int) -> String? {
        storage.attribute(.blockDecoration, at: index, effectiveRange: nil) as? String
    }

    private func width(_ text: String, _ font: NSFont) -> CGFloat {
        InlineStyle.width(of: text, in: font)
    }

    @Test func listsFencedBlocks() {
        // "```math" 0–6, "x" 8, "```" 10–12, "$$" 14–15, "y" 17, "$$" 19–20, "```mermaid" 22–31, "graph TD" 33–40 (unclosed).
        let text = "```math\nx\n```\n$$\ny\n$$\n```mermaid\ngraph TD"
        let blocks = InlineStyle.fencedBlocks(in: MarkdownHighlighter.tokens(in: text), text: text as NSString)
        #expect(blocks == [
            InlineStyle.FencedBlock(range: NSRange(location: 0, length: 13), info: "math", lines: ["x"], closing: 10),
            InlineStyle.FencedBlock(range: NSRange(location: 14, length: 7), info: "math", lines: ["y"], closing: 19),
            InlineStyle.FencedBlock(range: NSRange(location: 22, length: 19), info: "mermaid", lines: ["graph TD"], closing: nil),
        ])
        #expect(blocks.map(\.isMath) == [true, true, false] && blocks.map(\.isDiagram) == [false, false, true])
        #expect(InlineStyle.diagramBlocks(in: MarkdownHighlighter.tokens(in: text), text: text as NSString) == [InlineStyle.DiagramBlock(range: NSRange(location: 22, length: 19), source: "graph TD")])
    }

    @Test func drawsMathInPlaceOfItsTeX() {
        let picture = MathPicture(image: NSImage(size: NSSize(width: 300, height: 60)), size: NSSize(width: 300, height: 60), baseline: 40)
        // "a $x$ b\n" 0–7 (token 2–4), "$$z$$\n" 8–13, "```math\n" 14–21, "y\n" 22–23, "```" 24–26.
        let text = "a $x$ b\n$$z$$\n```math\ny\n```"
        let storage = NSTextStorage(string: text, attributes: style.baseAttributes)
        var asked: [String] = []
        let resolved = InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: storage, math: { tex, display in
            asked.append("\(tex):\(display)")
            return tex == "z" ? nil : picture
        }, revealed: NSRange(location: 0, length: 0), textWidth: 200)
        #expect(asked == ["x:false", "z:true", "y:true"])
        #expect(resolved.math == [2: 2, 14: 24] && resolved.pictureBlocks == [NSRange(location: 14, length: 13)])
        // Fitted to the text width, baseline scaled along.
        let inline = storage.attribute(.mathPicture, at: 2, effectiveRange: nil) as? MathPicture
        #expect(inline?.size == NSSize(width: 200, height: 40) && inline?.baseline == 27)
        #expect(storage.attribute(.mathPicture, at: 8, effectiveRange: nil) == nil && storage.attribute(.mathPicture, at: 3, effectiveRange: nil) == nil)
        #expect((storage.attribute(.mathPicture, at: 24, effectiveRange: nil) as? MathPicture)?.size.width == 200)
        #expect(decoration(storage, 22) == nil && decoration(storage, 14) == nil)
        #expect(paragraph(storage, 24)?.alignment == .center && paragraph(storage, 0)?.alignment != .center)
        // A revealed formula stays TeX.
        let shown = NSTextStorage(string: text, attributes: style.baseAttributes)
        let none = InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: shown, math: { _, _ in picture }, revealed: NSRange(location: 0, length: 8), textWidth: 200)
        #expect(none.math == [8: 8, 14: 24] && shown.attribute(.mathPicture, at: 2, effectiveRange: nil) == nil)
    }

    /// Outside the caret's line the text takes the page's look: the system font at the theme's
    /// body and heading sizes, its line height, a divider under h1 and h2.
    @Test func rendersHeadingsAndTextLikeThePage() {
        // "# Title *em* `c`" 0–15 (em 9–10, c 14), "###### six" 17–26 (six 24–26).
        let text = storage("# Title *em* `c`\n###### six")
        let h1 = font(text, 2)
        #expect(h1.pointSize == 32 && !h1.isFixedPitch && NSFontManager.shared.weight(of: h1) >= 8)
        #expect(font(text, 9).fontDescriptor.symbolicTraits.contains(.italic) && font(text, 9).pointSize == 32)
        #expect(font(text, 14).isFixedPitch && abs(font(text, 14).pointSize - 32 * 0.85) < 0.01)
        #expect(color(text, 0) == style.muted && color(text, 17) == style.muted)
        #expect(abs(font(text, 24).pointSize - 13.6) < 0.01 && color(text, 24) == style.muted)
        #expect(decoration(text, 0) == "heading" && decoration(text, 17) == nil)
        #expect((paragraph(text, 0)?.paragraphSpacing ?? 0) == 10 && (paragraph(text, 17)?.paragraphSpacing ?? 0) == 0)
        let plain = storage("plain")
        #expect(font(plain, 0) == style.body && style.body.pointSize == 16 && !style.body.isFixedPitch)
        #expect(abs((paragraph(plain, 0)?.lineHeightMultiple ?? 0) - style.lineHeightMultiple(for: style.body, lineHeight: 1.5)) < 0.001)
    }

    /// The caret's lines keep the source look: SF Mono, the source coloring, nothing hidden by attributes.
    @Test func revealedLinesKeepTheSourceLook() {
        // "# Title\n" 0–7, "text `c`\n" 8–16, "- item" 17–22.
        let text = "# Title\ntext `c`\n- item"
        let shown = NSTextStorage(string: text, attributes: style.baseAttributes)
        InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: shown, revealed: NSRange(location: 8, length: 9))
        #expect(font(shown, 2).pointSize == 32 && font(shown, 20) == style.body)
        #expect(font(shown, 8) == style.regular && font(shown, 14) == style.regular)
        #expect(color(shown, 14) == style.code && shown.attribute(.backgroundColor, at: 14, effectiveRange: nil) == nil)
        #expect(paragraph(shown, 8)?.headIndent == 0 && paragraph(shown, 17)?.headIndent ?? 0 > 0)
        let heading = NSTextStorage(string: text, attributes: style.baseAttributes)
        InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: heading, revealed: NSRange(location: 0, length: 8))
        #expect(font(heading, 2) == style.bold && color(heading, 0) == style.accent && decoration(heading, 0) == nil)
        #expect(InlineStyle.complement(of: NSRange(location: 8, length: 9), in: NSRange(location: 0, length: 23)) == [NSRange(location: 0, length: 8), NSRange(location: 17, length: 6)])
        #expect(InlineStyle.complement(of: NSRange(location: 0, length: 0), in: NSRange(location: 0, length: 23)) == [NSRange(location: 0, length: 23)])
    }

    /// The caret's lines take the page's rhythm in the source font, their text centered in each line
    /// (the room for the band around them is added in layout, by `ThemedTextView`).
    @Test func revealedLinesTakeThePageRhythm() {
        // "a\n" 0–1, "b\n" 2–3, "c\n" 4–5, "d\n" 6–7, "e" 8.
        let text = "a\nb\nc\nd\ne"
        let shown = NSTextStorage(string: text, attributes: style.baseAttributes)
        InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: shown, revealed: NSRange(location: 2, length: 6))
        let layoutManager = NSLayoutManager()
        shown.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 400, height: 1000))
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        #expect(font(shown, 4) == style.regular && font(shown, 8) == style.body)
        for index in [2, 4, 6] {
            // The fragment, and the mono line box inside it found from the baseline.
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let top = rect.minY + layoutManager.location(forGlyphAt: glyph).y - layoutManager.defaultBaselineOffset(for: style.regular)
            let bottom = top + layoutManager.defaultLineHeight(for: style.regular)
            #expect(abs(rect.height - style.regular.pointSize * 1.5) < 0.01, "line at \(index): \(rect)")
            #expect(abs((top - rect.minY) - (rect.maxY - bottom)) < 0.01, "line at \(index): text from \(top) to \(bottom) in \(rect)")
        }
    }

    @Test func inlineConstructsStyleTheirText() {
        let text = storage("**b** ~~s~~ `c` [t](https://x) <https://y>")
        #expect(font(text, 2).fontDescriptor.symbolicTraits.contains(.bold) && color(text, 0) == style.muted && !font(text, 2).isFixedPitch)
        #expect(text.attribute(.strikethroughStyle, at: 8, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(color(text, 13) == style.foreground && font(text, 13).isFixedPitch && text.attribute(.backgroundColor, at: 13, effectiveRange: nil) != nil)
        #expect(text.attribute(.link, at: 17, effectiveRange: nil) as? String == "https://x" && color(text, 17) == style.accent)
        #expect(text.attribute(.link, at: 31, effectiveRange: nil) as? String == "https://y")
    }

    @Test func listsHangQuotesIndentCodeDecorates() {
        // "- item\n" 0–6, "> q\n" 7–10, "```\n" 11–14, "x\n" 15–16, "```\n" 17–20, "---\n" 21–24, "- [x] done" 25–34 (box 27–29).
        let text = storage("- item\n> q\n```\nx\n```\n---\n- [x] done")
        #expect(abs((paragraph(text, 3)?.headIndent ?? 0) - width("• ", style.body)) < 0.01 && paragraph(text, 3)?.firstLineHeadIndent == 0)
        #expect(color(text, 0) == style.foreground)
        #expect(paragraph(text, 9)?.firstLineHeadIndent == InlineStyle.quoteIndent && decoration(text, 9) == "quote:1")
        #expect(decoration(text, 15) == "code" && color(text, 15) == style.foreground && font(text, 15).isFixedPitch)
        #expect(decoration(text, 11) == "code" && color(text, 11) == style.muted)
        #expect(paragraph(text, 15)?.headIndent == InlineStyle.codeIndent)
        #expect(decoration(text, 21) == "rule")
        #expect(text.attribute(.taskBox, at: 27, effectiveRange: nil) as? String == "checked")
        // The box's middle character is kerned out to the box's room; the item hangs by the visible prefix plus that room.
        let kern = text.attribute(.kern, at: 28, effectiveRange: nil) as? CGFloat
        #expect(abs((kern ?? 0) - (InlineStyle.taskBoxWidth - width("x", style.body))) < 0.001)
        #expect(abs((paragraph(text, 31)?.headIndent ?? 0) - (width("• x ", style.body) + (kern ?? 0))) < 0.01)
    }

    @Test func calloutsTintHangAndTitleTheirFirstLine() {
        // Lines: title 0–10, body 12–17, deeper 19–29, plain quote 31–33, after 35–39.
        let text = "> [!tip] Hi\n> body\n> > deeper\n\n> q\nafter"
        let storage = storage(text)
        let tip = style.calloutColor(for: .tip)
        #expect(decoration(storage, 0) == "callout:tip" && decoration(storage, 12) == "callout:tip" && decoration(storage, 19) == "callout:tip|quote")
        #expect(decoration(storage, 31) == "quote:1" && decoration(storage, 35) == nil)
        #expect(font(storage, 9) == style.calloutTitleFont && color(storage, 9) == tip)
        #expect(color(storage, 14) == style.foreground && color(storage, 32) == style.muted)
        #expect(paragraph(storage, 0)?.firstLineHeadIndent == InlineStyle.quoteIndent + InlineStyle.calloutIconSize + InlineStyle.calloutIconGap)
        #expect(paragraph(storage, 0)?.paragraphSpacingBefore == InlineStyle.calloutPadding)
        #expect(paragraph(storage, 12)?.headIndent == InlineStyle.quoteIndent && paragraph(storage, 19)?.headIndent == 2 * InlineStyle.quoteIndent)
        #expect(paragraph(storage, 19)?.paragraphSpacing == InlineStyle.calloutPadding && paragraph(storage, 12)?.paragraphSpacing == 0)
        let title = storage.attribute(.calloutTitle, at: 0, effectiveRange: nil) as? CalloutTitle
        #expect(title?.type == "tip" && title?.depth == 1 && title?.defaultTitle == nil)
        #expect(storage.attribute(.calloutTitle, at: 12, effectiveRange: nil) == nil)
        let untitled = self.storage("> [!Warning]\n> body")
        #expect((untitled.attribute(.calloutTitle, at: 0, effectiveRange: nil) as? CalloutTitle)?.defaultTitle == "Warning")
        #expect(color(untitled, 3) == style.muted)
        #expect(style.calloutColor(for: .danger) == NSColor(rgb: 0xCF222E))
        #expect(EditorStyle(theme: .macOS, isDark: false).calloutColor(for: .tip) == .systemTeal)
    }

    @Test func layoutManagerPaintsCalloutsAndTheirIcon() {
        // Lines end at 5, 17, 24 and 29.
        let text = "plain\n> [!tip] Hi\n> body\nafter"
        let storage = NSTextStorage(string: text, attributes: style.baseAttributes)
        InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: storage)
        let layoutManager = InlineLayoutManager()
        layoutManager.calloutColors = [.tip: .red]
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 200, height: 1000))
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 200).fill()
        context.cgContext.translateBy(x: 0, y: 200)
        context.cgContext.scaleBy(x: 1, y: -1)
        layoutManager.drawBackground(forGlyphRange: layoutManager.glyphRange(for: container), at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        let ends = [5, 17, 24, 29]
        func rect(_ line: Int) -> NSRect { layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: ends[line]), effectiveRange: nil) }
        func pixel(_ x: CGFloat, _ line: Int, _ fraction: CGFloat = 0.5) -> NSColor? {
            let rect = rect(line)
            return rep.colorAt(x: Int(x), y: Int(rect.minY + rect.height * fraction))
        }
        func isTinted(_ color: NSColor?) -> Bool { color.map { $0.redComponent > 0.95 && $0.greenComponent > 0.8 && $0.greenComponent < 0.95 } ?? false }
        func isWhite(_ color: NSColor?) -> Bool { color.map { $0.redComponent > 0.99 && $0.greenComponent > 0.99 } ?? false }
        #expect(isWhite(pixel(150, 0)) && isTinted(pixel(150, 1)) && isTinted(pixel(150, 2)) && isWhite(pixel(150, 3)))
        // The top corners are rounded: the very corner stays white, a little further in it is tinted.
        #expect(isWhite(pixel(0.5, 1, 0.02)) && isTinted(pixel(0.5, 1, 0.5)))
        // The icon (full red) sits in the title line between the container padding + indent and the title.
        let title = rect(1)
        var strokes = 0
        for x in Int(container.lineFragmentPadding + InlineStyle.quoteIndent)...Int(container.lineFragmentPadding + InlineStyle.quoteIndent + InlineStyle.calloutIconSize) {
            for y in Int(title.minY)...Int(title.maxY - 1) where rep.colorAt(x: x, y: y).map({ $0.redComponent > 0.9 && $0.greenComponent < 0.5 }) == true {
                strokes += 1
            }
        }
        #expect(strokes > 10)
    }

    @Test func imagesReserveSpaceAndHideMarkers() {
        let picture = NSImage(size: NSSize(width: 200, height: 100))
        func provider(_ destination: String) -> NSImage? { destination == "pic.png" ? picture : nil }
        let text = "![a](pic.png)\n![b](missing.png)"
        let wide = NSTextStorage(string: text, attributes: style.baseAttributes)
        let resolved = InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: wide, images: provider, textWidth: 400)
        #expect(resolved.images == [0] && resolved.diagrams.isEmpty)
        #expect(paragraph(wide, 0)?.paragraphSpacing == 108)
        #expect((wide.attribute(.inlineImage, at: 0, effectiveRange: nil) as? InlineImage)?.size == NSSize(width: 200, height: 100))
        #expect((paragraph(wide, 14)?.paragraphSpacing ?? 0) == 0)
        #expect(wide.attribute(.inlineImage, at: 14, effectiveRange: nil) == nil)
        let narrow = NSTextStorage(string: text, attributes: style.baseAttributes)
        InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: narrow, images: provider, textWidth: 100)
        #expect((narrow.attribute(.inlineImage, at: 0, effectiveRange: nil) as? InlineImage)?.size == NSSize(width: 100, height: 50))
        #expect(paragraph(narrow, 0)?.paragraphSpacing == 58)
        // A revealed paragraph is source: no picture.
        let shown = NSTextStorage(string: text, attributes: style.baseAttributes)
        let none = InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: shown, images: provider, revealed: NSRange(location: 0, length: 14), textWidth: 400)
        #expect(none.images.isEmpty && shown.attribute(.inlineImage, at: 0, effectiveRange: nil) == nil)
    }

    @Test func layoutManagerDrawsImagesUnderTheirLine() {
        let picture = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let text = "![a](pic.png)\nafter"
        let storage = NSTextStorage(string: text, attributes: style.baseAttributes)
        InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: storage, images: { _ in picture }, textWidth: 400)
        let layoutManager = InlineLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 400, height: 1000))
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        // The page's line height (16 px × 1.5) plus the picture and its gap.
        let first = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        #expect(abs(first.height - (24 + 28)) < 1, "first line \(first.height)")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 100).fill()
        context.cgContext.translateBy(x: 0, y: 100)
        context.cgContext.scaleBy(x: 1, y: -1)
        layoutManager.drawBackground(forGlyphRange: layoutManager.glyphRange(for: container), at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        func isRed(_ x: Int, _ y: Int) -> Bool { rep.colorAt(x: x, y: y).map { $0.redComponent > 0.9 && $0.greenComponent < 0.1 } ?? false }
        let top = Int(first.height - InlineStyle.imageGap / 2 - 20)
        #expect(isRed(20, top + 2) && isRed(39, top + 10) && isRed(20, top + 18))
        #expect(!isRed(20, top - 4) && !isRed(20, top + 24) && !isRed(60, top + 10))
    }

    /// A table in a file with Windows line breaks aligns like one with Unix ones: rows were grouped by
    /// `\n` alone, so with `\r\n` every row stood on its own and nothing was padded.
    /// A cell that ends with an emoji is padded on the emoji itself: the kern used to land on its second
    /// UTF-16 unit, which TextKit ignores, so that row's pipes stood out of line.
    @Test func paddingAfterAnEmojiLandsOnIt() {
        let text = storage("|a😀|b|\n|--|--|\n|cccccc|d|")
        let emoji = ("|a😀|b|" as NSString).range(of: "😀")
        let kern = text.attribute(.kern, at: emoji.location, effectiveRange: nil) as? CGFloat
        #expect((kern ?? 0) > 0)
        #expect(text.attribute(.kern, at: emoji.location + 1, effectiveRange: nil) as? CGFloat == kern)
    }

    @Test func tablesAlignWithWindowsLineBreaks() {
        let unix = storage("| a | **b** |\n|:--|--:|\n| cc | d |")
        let windows = storage("| a | **b** |\r\n|:--|--:|\r\n| cc | d |")
        func padding(_ text: NSTextStorage) -> [CGFloat] {
            (0..<text.length).compactMap { text.attribute(.kern, at: $0, effectiveRange: nil) as? CGFloat }
        }
        #expect(!padding(unix).isEmpty)
        #expect(padding(windows) == padding(unix))
    }

    @Test func tablesAlignByKerningAndStyleTheHeader() {
        // Lines: "| a | **b** |" 0–12, "|:--|--:|" 14–22, "| cc | d |" 24–33, "| e | ffff |" 35–46.
        let text = storage("| a | **b** |\n|:--|--:|\n| cc | d |\n| e | ffff |")
        let bold = NSFontManager.shared.convert(style.body, toHaveTrait: .boldFontMask)
        func kern(_ index: Int) -> CGFloat? { text.attribute(.kern, at: index, effectiveRange: nil) as? CGFloat }
        let column0 = max(width(" a ", bold), width(" cc ", style.body), width(" e ", style.body))
        let column1 = max(width(" b ", bold), width(" d ", style.body), width(" ffff ", style.body))
        // Padding in points: after the last visible character (left), on the leading space (right).
        #expect(abs((kern(3) ?? 0) - (column0 - width(" a ", bold))) < 0.01)
        #expect(abs((kern(5) ?? 0) - (column1 - width(" b ", bold))) < 0.01)
        #expect(kern(28) == nil && abs((kern(30) ?? 0) - (column1 - width(" d ", style.body))) < 0.01)
        #expect(abs((kern(38) ?? 0) - (column0 - width(" e ", style.body))) < 0.01 && kern(45) == nil)
        #expect(font(text, 2).fontDescriptor.symbolicTraits.contains(.bold) && !font(text, 26).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(color(text, 4) == style.muted && color(text, 0) == style.muted)
        #expect(decoration(text, 14) == "rule" && color(text, 14) == style.muted)
        // A revealed row is raw and unpadded; the others keep their columns.
        let shown = NSTextStorage(string: text.string, attributes: style.baseAttributes)
        InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text.string), to: shown, revealed: NSRange(location: 0, length: 14))
        #expect(shown.attribute(.kern, at: 3, effectiveRange: nil) == nil)
        #expect(shown.attribute(.kern, at: 30, effectiveRange: nil) as? CGFloat == kern(30))
    }

    @Test func footnotesAndHtmlAreStyled() {
        let text = storage("see[^1] <b>x</b>\n[^1]: note")
        #expect(font(text, 5).pointSize == 11 && text.attribute(.baselineOffset, at: 5, effectiveRange: nil) as? CGFloat == 5)
        #expect(color(text, 5) == style.accent && color(text, 3) == style.muted)
        #expect(color(text, 8) == style.muted && font(text, 11).pointSize == 16)
        #expect(color(text, 17) == style.muted && color(text, 23) == style.foreground)
    }

    @Test func fontsFollowTheTextSize() {
        let big = EditorStyle(theme: .macOS, isDark: false, size: 26)
        #expect(big.regular.pointSize == 26 && big.bold.pointSize == 26 && big.italic.pointSize == 26)
        #expect(big.body.pointSize == 30 && big.heading(level: 1).pointSize == 52 && big.heading(level: 6).pointSize == 26)
        #expect(big.codeFont(within: big.body).pointSize == 25.5)
        let normal = EditorStyle(theme: .macOS, isDark: false)
        #expect(normal.body.pointSize == 15 && normal.heading(level: 1).pointSize == 26 && normal.heading(level: 3).pointSize == 17)
        #expect(NSFontManager.shared.weight(of: normal.heading(level: 1)) > NSFontManager.shared.weight(of: normal.heading(level: 3)))
        #expect(EditorStyle(theme: .github, isDark: false).heading(level: 2).pointSize == 24)
    }

    @Test func htmlElementsAreStyledAndAligned() {
        let text = storage("<b>x</b> <i>y</i> <a href=\"u\">z</a> <!-- c --> \\*e\n<div align=\"center\">w</div>\n<kbd>K1</kbd> <mark>M1</mark> <sup>S1</sup> <h2>T1</h2>")
        func at(_ needle: String) -> Int { (text.string as NSString).range(of: needle).location }
        #expect(font(text, at("x")).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(font(text, at("y")).fontDescriptor.symbolicTraits.contains(.italic))
        #expect(color(text, at("z")) == style.accent && text.attribute(.link, at: at("z"), effectiveRange: nil) as? String == "u")
        #expect(color(text, at("<b>")) == style.muted && color(text, at("<!--")) == style.muted && color(text, at("\\*")) == style.muted)
        #expect(paragraph(text, at("w"))?.alignment == .center && paragraph(text, at("x"))?.alignment != .center)
        #expect(font(text, at("K1")).isFixedPitch && text.attribute(.backgroundColor, at: at("K1"), effectiveRange: nil) != nil)
        #expect(text.attribute(.backgroundColor, at: at("M1"), effectiveRange: nil) != nil && text.attribute(.backgroundColor, at: at("<mark>"), effectiveRange: nil) == nil)
        #expect(font(text, at("S1")).pointSize == 11 && text.attribute(.baselineOffset, at: at("S1"), effectiveRange: nil) as? CGFloat == 5)
        #expect(font(text, at("T1")).pointSize == 24)
    }

    @Test func layoutManagerDrawsTaskBoxesOnlyWhileHidden() {
        let view = ThemedTextView.standalone()
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        view.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        view.presentation = .inline
        view.replaceText(with: "- [ ] a\n- [x] b\nend")
        view.setSelectedRange(NSRange(location: 18, length: 0))
        let layoutManager = view.layoutManager as! InlineLayoutManager
        layoutManager.lineColor = .blue
        layoutManager.accent = .green
        func render() -> NSBitmapImageRep {
            layoutManager.ensureLayout(for: view.textContainer!)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 400, height: 100).fill()
            context.cgContext.translateBy(x: 0, y: 100)
            context.cgContext.scaleBy(x: 1, y: -1)
            layoutManager.drawBackground(forGlyphRange: layoutManager.glyphRange(for: view.textContainer!), at: view.textContainerOrigin)
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        /// The middle of a line's fragment, found from its line break (hidden glyphs at a line start sit on the previous fragment).
        func mid(_ line: Int) -> Int {
            let newline = NSMaxRange(view.lineIndex.range(ofLine: line))
            let glyph = layoutManager.glyphIndexForCharacter(at: min(newline, (view.string as NSString).length - 1))
            return Int(layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).midY + view.textContainerOrigin.y)
        }
        let left = Int(view.textContainerOrigin.x)
        func columns(_ rep: NSBitmapImageRep, y: Int, _ test: (NSColor) -> Bool) -> [Int] {
            (0..<80).filter { x in rep.colorAt(x: left + x, y: y).map(test) ?? false }
        }
        let blue: (NSColor) -> Bool = { $0.blueComponent > 0.6 && $0.redComponent < 0.6 }
        let green: (NSColor) -> Bool = { $0.greenComponent > 0.9 && $0.redComponent < 0.1 }
        let hidden = render()
        // Line 0: the outline's two sides; line 1: a filled square about 14 pt wide, after the bullet.
        let sides = columns(hidden, y: mid(0), blue)
        #expect(sides.count >= 2 && (sides.last ?? 0) - (sides.first ?? 0) > 10, "\(sides)")
        // The white check mark cuts through the green at mid height, so the run is measured by its ends.
        let filled = columns(hidden, y: mid(1), green)
        #expect(filled.count >= 4 && (filled.last ?? 0) - (filled.first ?? 0) >= 9 && (filled.first ?? 0) > 5, "\(filled)")
        #expect(columns(hidden, y: mid(0), green).isEmpty)
        view.setSelectedRange(NSRange(location: 6, length: 0))
        let revealed = render()
        #expect(columns(revealed, y: mid(0), blue).isEmpty)
        let still = columns(revealed, y: mid(1), green)
        #expect(still.count >= 4 && (still.last ?? 0) - (still.first ?? 0) >= 9, "\(still)")
    }

    @Test func layoutManagerPaintsDecorationsBehindTheRightLines() {
        // Lines end at 5, 9, 14, 18, 22, 26 (their line breaks) and 31 (the last character).
        let text = "plain\n```\ncode\n```\n> q\n---\nafter"
        let storage = NSTextStorage(string: text, attributes: style.baseAttributes)
        InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: storage)
        let layoutManager = InlineLayoutManager()
        layoutManager.codeBackground = .red
        layoutManager.lineColor = .blue
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 200, height: 1000))
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 200).fill()
        context.cgContext.translateBy(x: 0, y: 200)
        context.cgContext.scaleBy(x: 1, y: -1)
        layoutManager.drawBackground(forGlyphRange: layoutManager.glyphRange(for: container), at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        let ends = [5, 9, 14, 18, 22, 26, 31]
        func pixel(_ x: CGFloat, _ line: Int, _ fraction: CGFloat = 0.5) -> NSColor? {
            let rect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: ends[line]), effectiveRange: nil)
            return rep.colorAt(x: Int(x), y: Int(rect.minY + rect.height * fraction))
        }
        func isRed(_ color: NSColor?) -> Bool { color.map { $0.redComponent > 0.9 && $0.greenComponent < 0.1 } ?? false }
        func isBlue(_ color: NSColor?) -> Bool { color.map { $0.blueComponent > 0.9 && $0.redComponent < 0.1 } ?? false }
        #expect(!isRed(pixel(100, 0)) && isRed(pixel(100, 1)) && isRed(pixel(100, 2)) && isRed(pixel(100, 3)) && !isRed(pixel(100, 4)))
        #expect(!isRed(pixel(0.5, 1, 0.05)) && isRed(pixel(0.5, 2, 0.05)))
        #expect(isBlue(pixel(3, 4)) && !isBlue(pixel(30, 4)))
        #expect(isBlue(pixel(100, 5)) && !isBlue(pixel(100, 5, 0.2)))
        #expect(!isRed(pixel(100, 6)) && !isBlue(pixel(100, 6)))
    }
}
