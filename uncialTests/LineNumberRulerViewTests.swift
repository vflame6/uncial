import AppKit
import Testing
@testable import Uncial

@MainActor
@Suite struct LineNumberRulerViewTests {
    /// macOS 14 stopped clipping views to their bounds, and the scroll view hands the ruler a dirty rect
    /// as wide as itself; the gutter must paint only its own strip or it covers the text.
    @Test func paintsOnlyInsideItsBounds() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        let textView = ThemedTextView.standalone()
        textView.frame = NSRect(x: 0, y: 0, width: 500, height: 100)
        textView.replaceText(with: "one\ntwo\nthree")
        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true
        ruler.frame = NSRect(x: 0, y: 0, width: 37, height: 100)

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 500, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 500, height: 100).fill()
        ruler.draw(NSRect(x: 0, y: 0, width: 500, height: 100))
        NSGraphicsContext.restoreGraphicsState()

        func isRed(_ x: Int, _ y: Int) -> Bool { rep.colorAt(x: x, y: y).map { $0.redComponent > 0.9 && $0.greenComponent < 0.1 } ?? false }
        #expect(isRed(200, 50) && isRed(499, 10) && isRed(38, 50))
        #expect(!isRed(5, 50) && !isRed(30, 90))
    }

    /// A number sits on its line's baseline: Live Preview lines have room above their text (the page's
    /// line height, the band around the caret's lines), which a number drawn at the line's top misses.
    /// An empty line's number sits where a line of text in its style would have its baseline.
    @Test func numbersSitOnTheirLinesBaseline() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        let textView = ThemedTextView.standalone()
        textView.frame = NSRect(x: 0, y: 0, width: 500, height: 200)
        textView.presentation = .inline
        // "one\n" 0–3, "two\n" 4–7, "\n" 8, "four" 9–12.
        textView.replaceText(with: "one\ntwo\n\nfour")
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true
        ruler.frame = NSRect(x: 0, y: 0, width: 37, height: 200)
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)

        let rep = ruler.bitmapImageRepForCachingDisplay(in: ruler.bounds)!
        ruler.cacheDisplay(in: ruler.bounds, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / ruler.bounds.height
        let background = rep.colorAt(x: 1, y: 1)
        func inRuler(_ y: CGFloat) -> CGFloat {
            ruler.convert(NSPoint(x: 0, y: y + textView.textContainerInset.height), from: textView).y
        }
        func fragment(_ index: Int) -> NSRect {
            layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index), effectiveRange: nil)
        }
        /// The lowest inked row inside the line: where the number's digits stand.
        func digitsBottom(_ index: Int) -> CGFloat? {
            var lowest: CGFloat?
            for row in Int(inRuler(fragment(index).minY) * scale)..<Int(inRuler(fragment(index).maxY) * scale)
            where (0..<rep.pixelsWide).contains(where: { rep.colorAt(x: $0, y: row) != background }) {
                lowest = CGFloat(row + 1) / scale
            }
            return lowest
        }
        for index in [0, 4, 9] {
            let baseline = inRuler(fragment(index).minY + layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index)).y)
            #expect(digitsBottom(index).map { abs($0 - baseline) <= 1.5 } ?? false, "line at \(index): digits end at \(String(describing: digitsBottom(index))), text baseline \(baseline)")
        }
        // The empty line is a rendered line like "one": the same baseline in its fragment.
        let rendered = layoutManager.location(forGlyphAt: 0).y
        let empty = inRuler(fragment(8).minY + rendered)
        #expect(digitsBottom(8).map { abs($0 - empty) <= 1.5 } ?? false, "empty line: digits end at \(String(describing: digitsBottom(8))), expected \(empty)")
    }
}
