import AppKit

/// Gutter with one number per logical line; wrapped continuation rows stay blank. Draws from the
/// text view's layout manager, in the editor's font and palette.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: ThemedTextView?
    private var observers: [NSObjectProtocol] = []

    init(textView: ThemedTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        clipsToBounds = true
        textView.postsFrameChangedNotifications = true
        let redraw: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main, using: redraw),
            center.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main, using: redraw),
            center.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: .main, using: redraw),
        ]
        invalidate()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override var isFlipped: Bool { true }

    /// Recomputes the width for the current line count and redraws. The text view calls it after every change.
    func invalidate() {
        guard let textView else { return }
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: textView.style.regular]).width
        let thickness = GutterMetrics(lineCount: textView.lineIndex.count, digitWidth: digitWidth).thickness
        if thickness != ruleThickness {
            ruleThickness = thickness
            scrollView?.tile()
        }
        needsDisplay = true
    }

    /// The scroll view hands a ruler a dirty rect as wide as itself, and since macOS 14 views do not
    /// clip to their bounds, so painting the whole rect would cover the document.
    override func draw(_ dirtyRect: NSRect) {
        guard let textView else { return }
        let area = dirtyRect.intersection(bounds)
        textView.style.background.setFill()
        area.fill()
        drawHashMarksAndLabels(in: area)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let style = textView.style
        let lineIndex = textView.lineIndex
        let inset = textView.textContainerInset
        let caretLine = lineIndex.line(at: textView.selectedRange().location)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        func draw(line: Int, fragment: NSRect) {
            let top = convert(NSPoint(x: 0, y: fragment.minY + inset.height), from: textView).y
            let box = NSRect(x: 0, y: top, width: ruleThickness - GutterMetrics.padding, height: fragment.height)
            guard box.intersects(rect) else { return }
            let color = line == caretLine ? style.foreground : style.muted
            (String(line + 1) as NSString).draw(in: box, withAttributes: [.font: style.regular, .foregroundColor: color, .paragraphStyle: paragraph])
        }
        var visible = textView.visibleRect
        visible.origin.x -= inset.width
        visible.origin.y -= inset.height
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        var glyph = glyphs.location
        var lastLine = -1
        while glyph < NSMaxRange(glyphs) {
            var fragmentGlyphs = NSRange()
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragmentGlyphs)
            guard fragmentGlyphs.length > 0 else { break }
            let line = lineIndex.line(at: layoutManager.characterIndexForGlyph(at: fragmentGlyphs.location))
            if line != lastLine {
                draw(line: line, fragment: fragment)
                lastLine = line
            }
            glyph = NSMaxRange(fragmentGlyphs)
        }
        if layoutManager.extraLineFragmentTextContainer != nil, lastLine != lineIndex.count - 1 {
            draw(line: lineIndex.count - 1, fragment: layoutManager.extraLineFragmentRect)
        }
    }
}
