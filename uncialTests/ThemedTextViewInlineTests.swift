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

    @Test func plainClickOnALinkPlacesTheCaret() {
        let inline = editor("[text](https://example.com) after", presentation: .inline, caret: 30)
        inline.clicked(onLink: "https://example.com", at: 3)
        #expect(inline.selectedRange() == NSRange(location: 3, length: 0))
        #expect(inline.revealed == NSRange(location: 0, length: 33))
    }
}
