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
}
