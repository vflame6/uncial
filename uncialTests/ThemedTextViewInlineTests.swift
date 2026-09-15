import AppKit
import Testing
@testable import Uncial

@MainActor
@Suite struct ThemedTextViewInlineTests {
    /// Lines: `## Heading` 0–10, `Some **bold** text` 11–29, `- item` 30–36, fence 37–40,
    /// `let x = 1` 41–50, fence 51–54.
    private let sample = "## Heading\nSome **bold** text\n- item\n```\nlet x = 1\n```"

    private func editor(_ text: String, presentation: EditorPresentation, caret: Int) -> ThemedTextView {
        let view = ThemedTextView.standalone()
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        view.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        view.presentation = presentation
        view.replaceText(with: text)
        view.setSelectedRange(NSRange(location: caret, length: 0))
        layout(view)
        return view
    }

    private func layout(_ view: ThemedTextView) {
        view.layoutManager?.ensureLayout(for: view.textContainer!)
    }

    /// Used width of a line's fragment, measured from its line break: hidden glyphs at a
    /// paragraph start attach to the previous fragment (probed 2026-09-15).
    private func width(_ view: ThemedTextView, line: Int) -> CGFloat {
        let range = view.lineIndex.range(ofLine: line)
        let index = min(NSMaxRange(range), (view.string as NSString).length - 1)
        let glyph = view.layoutManager!.glyphIndexForCharacter(at: index)
        return view.layoutManager!.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).width
    }

    @Test func hidesMarkersExceptOnTheCaretLine() {
        let source = editor(sample, presentation: .source, caret: 32)
        let inline = editor(sample, presentation: .inline, caret: 32)
        let advance = InlineStyle(style: inline.style).characterWidth
        let hiddenHeading = width(inline, line: 0)
        let hiddenBold = width(inline, line: 1)
        #expect(abs(hiddenBold - (width(source, line: 1) - 4 * advance)) < 0.5)
        #expect(abs(width(inline, line: 2) - width(source, line: 2)) < 0.5)
        #expect(width(inline, line: 3) < width(source, line: 3) - 2 * advance)
        #expect(inline.revealed == NSRange(location: 30, length: 7))

        inline.setSelectedRange(NSRange(location: 20, length: 0))
        layout(inline)
        #expect(inline.revealed == NSRange(location: 11, length: 19))
        #expect(abs(width(inline, line: 1) - width(source, line: 1)) < 0.5)
        #expect(abs(width(inline, line: 0) - hiddenHeading) < 0.5)

        inline.setSelectedRange(NSRange(location: 2, length: 0))
        layout(inline)
        #expect(width(inline, line: 0) > hiddenHeading + 2 * advance)
        #expect(abs(width(inline, line: 1) - hiddenBold) < 0.5)

        inline.setSelectedRange(NSRange(location: 43, length: 0))
        layout(inline)
        #expect(inline.revealed == NSRange(location: 37, length: 17))
        #expect(abs(width(inline, line: 3) - width(source, line: 3)) < 0.5)
        #expect(abs(width(inline, line: 0) - hiddenHeading) < 0.5)
    }

    @Test func drawsBulletsAndSwitchesBack() {
        let inline = editor("- item\ntext", presentation: .inline, caret: 8)
        let plain = editor("- item\ntext", presentation: .source, caret: 8)
        #expect(inline.layoutManager!.cgGlyph(at: 0) != plain.layoutManager!.cgGlyph(at: 0))
        #expect(inline.markers.bullets == [0])
        inline.presentation = .source
        layout(inline)
        #expect(inline.layoutManager!.cgGlyph(at: 0) == plain.layoutManager!.cgGlyph(at: 0))
        #expect(inline.markers == .empty)
    }

    /// Hidden glyphs at a paragraph start belong to the previous line's fragment; decorations
    /// must still land on their own lines only.
    @Test func decorationsStayOnTheirOwnLinesWhenMarkersAreHidden() {
        let text = "- plain\n---\nafter\n\n```\ncode\n```\n> q\n> > n\nend"
        let inline = editor(text, presentation: .inline, caret: (text as NSString).length)
        let layoutManager = inline.layoutManager as! InlineLayoutManager
        layoutManager.codeBackground = .red
        layoutManager.lineColor = .blue
        layout(inline)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 200).fill()
        context.cgContext.translateBy(x: 0, y: 200)
        context.cgContext.scaleBy(x: 1, y: -1)
        layoutManager.drawBackground(forGlyphRange: layoutManager.glyphRange(for: inline.textContainer!), at: inline.textContainerOrigin)
        NSGraphicsContext.restoreGraphicsState()
        let lineHeight = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
        let left = inline.textContainerOrigin.x
        func pixel(_ x: CGFloat, _ line: Int, _ fraction: CGFloat = 0.5) -> NSColor? {
            rep.colorAt(x: Int(left + x), y: Int(lineHeight * (CGFloat(line) + fraction)))
        }
        func isRed(_ color: NSColor?) -> Bool { color.map { $0.redComponent > 0.9 && $0.greenComponent < 0.1 } ?? false }
        func isBlue(_ color: NSColor?) -> Bool { color.map { $0.blueComponent > 0.9 && $0.redComponent < 0.1 } ?? false }
        #expect(!isBlue(pixel(100, 0)) && isBlue(pixel(100, 1)) && !isBlue(pixel(100, 2)))
        #expect(!isRed(pixel(100, 3)) && isRed(pixel(100, 4)) && isRed(pixel(100, 5)) && isRed(pixel(100, 6)) && !isRed(pixel(100, 7)))
        #expect(isBlue(pixel(3, 7)) && !isBlue(pixel(19, 7)))
        #expect(isBlue(pixel(3, 8)) && isBlue(pixel(19, 8)))
        #expect(!isBlue(pixel(3, 9)) && !isRed(pixel(100, 9)))
    }

    @Test func clickingATaskBoxTogglesIt() {
        let inline = editor("- [ ] task\nend", presentation: .inline, caret: 12)
        let layoutManager = inline.layoutManager!
        let middle = layoutManager.glyphIndexForCharacter(at: 3)
        let cell = layoutManager.boundingRect(forGlyphRange: NSRange(location: middle, length: 1), in: inline.textContainer!)
        let point = NSPoint(x: cell.midX + inline.textContainerOrigin.x, y: cell.midY + inline.textContainerOrigin.y)
        #expect(inline.taskBox(at: point) == NSRange(location: 2, length: 3))
        inline.toggle(taskBox: NSRange(location: 2, length: 3))
        #expect(inline.string.hasPrefix("- [x] task"))
        #expect(inline.selectedRange() == NSRange(location: 12, length: 0))
        #expect(inline.undoManager?.canUndo == true)
        inline.undoManager?.undo()
        #expect(inline.string.hasPrefix("- [ ] task"))
        inline.setSelectedRange(NSRange(location: 8, length: 0))
        layout(inline)
        #expect(inline.taskBox(at: point) == nil)
    }

    @Test func loadsLocalImagesOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-inline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let picture = NSImage(size: NSSize(width: 30, height: 10), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let png = NSBitmapImageRep(data: picture.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: directory.appendingPathComponent("file.png"))
        let inline = ThemedTextView.standalone()
        inline.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        inline.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        inline.baseURL = directory
        inline.presentation = .inline
        inline.replaceText(with: "![a](file.png)\n![r](https://x/y.png)\nend")
        inline.setSelectedRange(NSRange(location: 40, length: 0))
        layout(inline)
        #expect(inline.markers.isHidden(0) && !inline.markers.isHidden(15))
        #expect((inline.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing == 18)
        #expect(inline.textStorage!.attribute(.paragraphStyle, at: 15, effectiveRange: nil) == nil)
    }

    @Test func centersAReadableColumn() {
        let inline = editor(sample, presentation: .inline, caret: 32)
        #expect(inline.textContainerInset.width == 16)
        inline.setFrameSize(NSSize(width: 1000, height: 200))
        #expect(inline.textContainerInset.width == 140)
        inline.readableWidth = false
        #expect(inline.textContainerInset.width == 16)
        inline.readableWidth = true
        #expect(inline.textContainerInset.width == 140)
        inline.presentation = .source
        #expect(inline.textContainerInset.width == 16)
    }

    @Test func tableColumnsLineUpWhileHidden() {
        let text = "| a | **b** |\n|:--|--:|\n| cc | d |\nend"
        let inline = editor(text, presentation: .inline, caret: 36)
        let layoutManager = inline.layoutManager!
        func x(_ index: Int) -> CGFloat { layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index)).x }
        #expect(abs(x(4) - x(29)) < 0.5)
        #expect(x(29) > x(28) && x(4) > x(3) + 1.5 * InlineStyle(style: inline.style).characterWidth)
        #expect(width(inline, line: 1) < width(inline, line: 0) - 2 * InlineStyle(style: inline.style).characterWidth)
    }

    @Test func plainClickOnALinkPlacesTheCaret() {
        let inline = editor("[text](https://example.com) after", presentation: .inline, caret: 30)
        inline.clicked(onLink: "https://example.com", at: 3)
        #expect(inline.selectedRange() == NSRange(location: 3, length: 0))
        #expect(inline.revealed == NSRange(location: 0, length: 33))
    }
}
