import AppKit
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite struct InlineStyleTests {
    private let style = EditorStyle(palette: Theme.github.editorPalette, isDark: false)

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

    @Test func headingsGrowAndKeepMonospace() {
        let text = storage("# Title *em*\n###### six")
        #expect(font(text, 2).pointSize == 22 && font(text, 2).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(font(text, 2).isFixedPitch)
        #expect(font(text, 9).fontDescriptor.symbolicTraits.contains(.italic) && font(text, 9).pointSize == 22)
        #expect(color(text, 0) == style.muted && color(text, 20) == style.muted)
        #expect(font(text, 20).pointSize == 13)
    }

    @Test func inlineConstructsStyleTheirText() {
        let text = storage("**b** ~~s~~ `c` [t](https://x) <https://y>")
        #expect(font(text, 2).fontDescriptor.symbolicTraits.contains(.bold) && color(text, 0) == style.muted)
        #expect(text.attribute(.strikethroughStyle, at: 8, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(color(text, 13) == style.code && text.attribute(.backgroundColor, at: 13, effectiveRange: nil) != nil)
        #expect(text.attribute(.link, at: 17, effectiveRange: nil) as? String == "https://x" && color(text, 17) == style.accent)
        #expect(text.attribute(.link, at: 31, effectiveRange: nil) as? String == "https://y")
    }

    @Test func listsHangQuotesIndentCodeDecorates() {
        let inline = InlineStyle(style: style)
        let text = storage("- item\n> q\n```\nx\n```\n---\n- [x] done")
        #expect(paragraph(text, 3)?.headIndent == inline.characterWidth * 2 && paragraph(text, 3)?.firstLineHeadIndent == 0)
        #expect(color(text, 0) == style.accent)
        #expect(paragraph(text, 9)?.firstLineHeadIndent == InlineStyle.quoteIndent && decoration(text, 9) == "quote:1")
        #expect(decoration(text, 15) == "code" && color(text, 15) == style.code)
        #expect(decoration(text, 11) == "code" && color(text, 11) == style.muted)
        #expect(paragraph(text, 15)?.headIndent == InlineStyle.codeIndent)
        #expect(decoration(text, 21) == "rule")
        #expect(text.attribute(.taskBox, at: 28, effectiveRange: nil) as? String == "checked")
        #expect(paragraph(text, 31)?.headIndent == inline.characterWidth * 4)
    }

    @Test func imagesReserveSpaceAndHideMarkers() {
        let picture = NSImage(size: NSSize(width: 200, height: 100))
        func provider(_ destination: String) -> NSImage? { destination == "pic.png" ? picture : nil }
        let text = "![a](pic.png)\n![b](missing.png)"
        let wide = NSTextStorage(string: text, attributes: style.baseAttributes)
        let resolved = InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: wide, images: provider, textWidth: 400)
        #expect(resolved == [0])
        #expect(paragraph(wide, 0)?.paragraphSpacing == 108)
        #expect((wide.attribute(.inlineImage, at: 0, effectiveRange: nil) as? InlineImage)?.size == NSSize(width: 200, height: 100))
        #expect((paragraph(wide, 14)?.paragraphSpacing ?? 0) == 0)
        #expect(wide.attribute(.inlineImage, at: 14, effectiveRange: nil) == nil)
        let narrow = NSTextStorage(string: text, attributes: style.baseAttributes)
        InlineStyle(style: style).apply(MarkdownHighlighter.tokens(in: text), to: narrow, images: provider, textWidth: 100)
        #expect((narrow.attribute(.inlineImage, at: 0, effectiveRange: nil) as? InlineImage)?.size == NSSize(width: 100, height: 50))
        #expect(paragraph(narrow, 0)?.paragraphSpacing == 58)
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
        let first = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        #expect(abs(first.height - 44) < 0.5)
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
        #expect(isRed(20, 30) && isRed(40, 22) && isRed(20, 38))
        #expect(!isRed(20, 8) && !isRed(20, 50) && !isRed(60, 30))
    }

    @Test func tablesAlignByKerningAndStyleTheHeader() {
        let inline = InlineStyle(style: style)
        let text = storage("| a | **b** |\n|:--|--:|\n| cc | d |\n| e | ffff |")
        func kern(_ index: Int) -> CGFloat? { text.attribute(.kern, at: index, effectiveRange: nil) as? CGFloat }
        #expect(kern(3) == inline.characterWidth)
        #expect(kern(5) == 3 * inline.characterWidth)
        #expect(kern(28) == nil && kern(30) == 3 * inline.characterWidth)
        #expect(kern(38) == inline.characterWidth && kern(45) == nil)
        #expect(font(text, 2).fontDescriptor.symbolicTraits.contains(.bold) && !font(text, 26).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(color(text, 4) == style.muted && color(text, 0) == style.muted)
        #expect(decoration(text, 14) == "rule" && color(text, 14) == style.muted)
    }

    @Test func footnotesAndHtmlAreStyled() {
        let text = storage("see[^1] <b>x</b>\n[^1]: note")
        #expect(font(text, 5).pointSize == 10 && text.attribute(.baselineOffset, at: 5, effectiveRange: nil) as? CGFloat == 4)
        #expect(color(text, 5) == style.accent && color(text, 3) == style.muted)
        #expect(color(text, 8) == style.muted && font(text, 11).pointSize == 13)
        #expect(color(text, 17) == style.muted && color(text, 23) == style.foreground)
    }

    @Test func htmlElementsAreStyledAndAligned() {
        let text = storage("<b>x</b> <i>y</i> <a href=\"u\">z</a> <!-- c --> \\*e\n<div align=\"center\">w</div>\n<kbd>K1</kbd> <mark>M1</mark> <sup>S1</sup> <h2>T1</h2>")
        func at(_ needle: String) -> Int { (text.string as NSString).range(of: needle).location }
        #expect(font(text, at("x")).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(font(text, at("y")).fontDescriptor.symbolicTraits.contains(.italic))
        #expect(color(text, at("z")) == style.accent && text.attribute(.link, at: at("z"), effectiveRange: nil) as? String == "u")
        #expect(color(text, at("<b>")) == style.muted && color(text, at("<!--")) == style.muted && color(text, at("\\*")) == style.muted)
        #expect(paragraph(text, at("w"))?.alignment == .center && paragraph(text, at("x"))?.alignment != .center)
        #expect(color(text, at("K1")) == style.code && text.attribute(.backgroundColor, at: at("K1"), effectiveRange: nil) != nil)
        #expect(text.attribute(.backgroundColor, at: at("M1"), effectiveRange: nil) != nil && text.attribute(.backgroundColor, at: at("<mark>"), effectiveRange: nil) == nil)
        #expect(font(text, at("S1")).pointSize == 10 && text.attribute(.baselineOffset, at: at("S1"), effectiveRange: nil) as? CGFloat == 4)
        #expect(font(text, at("T1")).pointSize == InlineStyle.headingSizes[1])
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
        let left = Int(view.textContainerOrigin.x)
        func hasBlue(_ rep: NSBitmapImageRep, y: Int) -> Bool {
            (16...34).contains { x in rep.colorAt(x: left + x, y: y).map { $0.blueComponent > 0.6 && $0.redComponent < 0.6 } ?? false }
        }
        func isGreen(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Bool {
            rep.colorAt(x: x, y: y).map { $0.greenComponent > 0.9 && $0.redComponent < 0.1 } ?? false
        }
        let hidden = render()
        let advance = InlineStyle(style: view.style).characterWidth
        let middleX = left + Int(5 + 2.5 * advance)
        #expect(hasBlue(hidden, y: 8))
        #expect(isGreen(hidden, x: middleX, y: 20))
        #expect(!isGreen(hidden, x: middleX, y: 8))
        view.setSelectedRange(NSRange(location: 6, length: 0))
        let revealed = render()
        #expect(!hasBlue(revealed, y: 8))
        #expect(isGreen(revealed, x: middleX, y: 20))
    }

    @Test func layoutManagerPaintsDecorationsBehindTheRightLines() {
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
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 140, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 140).fill()
        context.cgContext.translateBy(x: 0, y: 140)
        context.cgContext.scaleBy(x: 1, y: -1)
        layoutManager.drawBackground(forGlyphRange: layoutManager.glyphRange(for: container), at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        let lineHeight = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
        func pixel(_ x: CGFloat, _ line: Int, _ fraction: CGFloat = 0.5) -> NSColor? {
            rep.colorAt(x: Int(x), y: Int(lineHeight * (CGFloat(line) + fraction)))
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
