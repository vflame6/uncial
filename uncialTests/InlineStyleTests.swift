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
        let text = storage("- item\n> q\n```\nx\n```\n---")
        #expect(paragraph(text, 3)?.headIndent == inline.characterWidth * 2 && paragraph(text, 3)?.firstLineHeadIndent == 0)
        #expect(color(text, 0) == style.accent)
        #expect(paragraph(text, 9)?.firstLineHeadIndent == InlineStyle.quoteIndent && decoration(text, 9) == "quote:1")
        #expect(decoration(text, 15) == "code" && color(text, 15) == style.code)
        #expect(decoration(text, 11) == "code" && color(text, 11) == style.muted)
        #expect(paragraph(text, 15)?.headIndent == InlineStyle.codeIndent)
        #expect(decoration(text, 21) == "rule")
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
