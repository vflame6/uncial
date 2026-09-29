import AppKit
import Testing
import UncialCore

/// `ThumbnailPage` is the thumbnail extension's typesetter, compiled into this bundle as well.
@MainActor
@Suite struct ThumbnailPageTests {
    /// The page of `markdown` in the GitHub theme's light colors, drawn 300 × 400 pixels.
    private func page(_ markdown: String) -> NSBitmapImageRep {
        bitmap(width: 300, height: 400, background: .clear, flipped: false) { context in
            ThumbnailPage(blocks: MarkdownOutline.blocks(in: markdown), palette: .light(for: .github)).draw(in: CGSize(width: 300, height: 400), context: context.cgContext)
        }
    }

    private func luminance(_ page: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        let color = page.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        return (color.redComponent + color.greenComponent + color.blueComponent) / 3
    }

    @Test func pageKeepsThePaperRatio() {
        #expect(ThumbnailPage.pageSize(fitting: CGSize(width: 512, height: 512)) == CGSize(width: 384, height: 512))
        #expect(ThumbnailPage.pageSize(fitting: CGSize(width: 300, height: 1000)) == CGSize(width: 300, height: 400))
        #expect(ThumbnailPage.pageSize(fitting: CGSize(width: 512, height: 512), atLeast: CGSize(width: 400, height: 0)) == CGSize(width: 400, height: 512))
    }

    @Test func palettesFollowTheTheme() {
        #expect(ThumbnailPage.Palette.light(for: .github).background == NSColor(rgb: 0xFFFFFF))
        #expect(ThumbnailPage.Palette.light(for: .solarized).background == NSColor(rgb: 0xFDF6E3))
        #expect(ThumbnailPage.Palette.light(for: .macOS).foreground == NSColor.labelColor)
    }

    @Test func headingsAreBiggerListsIndentedAndCodeMonospaced() {
        let blocks = MarkdownOutline.blocks(in: "# Title\n\nBody with `x` and **bold**.\n\n- item\n\n```\ncode\n```\n")
        let layout = ThumbnailPage.Layout(blocks: blocks, palette: .light(for: .github), width: 300, bodySize: 12)
        let fonts = layout.ranges.map { layout.storage.attribute(.font, at: $0.range.location, effectiveRange: nil) as! NSFont }
        #expect(fonts[0].pointSize == 24)
        #expect(fonts[1].pointSize == 12)
        #expect(fonts[3].isFixedPitch)
        let item = layout.storage.attributedSubstring(from: layout.ranges[2].range).string
        #expect(item.hasPrefix("•\t"))
        let paragraph = layout.storage.attribute(.paragraphStyle, at: layout.ranges[2].range.location, effectiveRange: nil) as! NSParagraphStyle
        #expect(paragraph.headIndent == 18)
        let bold = layout.storage.attributedSubstring(from: layout.ranges[1].range)
        var boldFont: NSFont?
        bold.enumerateAttribute(.font, in: NSRange(location: 0, length: bold.length)) { value, range, _ in
            if (bold.string as NSString).substring(with: range) == "bold" { boldFont = value as? NSFont }
        }
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    /// Code lines stay one paragraph (their breaks are U+2028), so the code box's tint covers all of them.
    @Test func codeTintCoversEveryLineOfTheBlock() {
        let page = page("```\nlet a = 1\nlet b = 2\nlet c = 3\n```\n")
        // Far right of the page: no glyphs there, only the tint of the code box.
        let tinted = (0..<400).filter { y in (0.85..<0.985).contains(luminance(page, 270, y)) }
        // Three code lines at body 9 pt are about 30 pt tall plus the box's padding.
        #expect(tinted.count > 30, "tint covers \(tinted.count) rows")
    }

    @Test func drawsThePageWithTextAndDecorations() {
        let page = page("# Heading\n\nSome text\n\n---\n\n```\nlet code = 1\n```\n")
        // Corners are the white page; the heading's line and the code box tint the paper; the bottom stays empty.
        #expect(luminance(page, 2, 2) > 0.98 && luminance(page, 297, 397) > 0.98)
        let topRows = (20..<60).map { y in (20..<280).map { x in luminance(page, x, y) }.min()! }
        #expect(topRows.min()! < 0.5, "no heading ink in the top band")
        let codeBand = (60..<200).flatMap { y in (30..<270).map { x in luminance(page, x, y) } }
        #expect(codeBand.filter { $0 < 0.97 && $0 > 0.88 }.count > 300, "no code tint")
        let bottom = (350..<398).flatMap { y in (2..<298).map { x in luminance(page, x, y) } }
        #expect(bottom.allSatisfy { $0 > 0.98 })
    }
}
