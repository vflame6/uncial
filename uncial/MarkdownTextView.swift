import AppKit
import SwiftUI
import UncialCore

/// Plain-text Markdown editor: SF Mono, soft wrap, no smart substitutions, native find bar and undo,
/// Markdown-aware coloring, and scroll reporting for Live Preview sync.
struct MarkdownTextView: NSViewRepresentable {
    let text: String
    let palette: EditorPalette?
    /// 1-based fractional document line to scroll to; a new token performs the scroll.
    var scrollTarget: ScrollTarget?
    let onChange: (String) -> Void
    /// Called with the 1-based fractional line at the top of the visible area when the user scrolls.
    var onScroll: ((Double) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange, onScroll: onScroll) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        // TextKit 1: NSLayoutManager gives the glyph ↔ point ↔ line math the sync needs.
        let textView = ThemedTextView(usingTextLayoutManager: false)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFontPanel = false
        textView.importsGraphics = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.delegate = context.coordinator
        textView.string = text
        textView.palette = palette
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.observeScrolling(of: scrollView)
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ThemedTextView else { return }
        context.coordinator.onChange = onChange
        context.coordinator.onScroll = onScroll
        if textView.palette != palette {
            textView.palette = palette
        }
        if textView.string != text {
            // External change (reload, another editor): replace the text, keep the caret in range, drop undo history.
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            let location = min(selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
            textView.undoManager?.removeAllActions()
            textView.rehighlight()
        }
        if let scrollTarget, scrollTarget.token != context.coordinator.appliedToken {
            context.coordinator.appliedToken = scrollTarget.token
            textView.scroll(toLine: scrollTarget.line - 1)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        var onScroll: ((Double) -> Void)?
        var appliedToken = 0
        weak var textView: ThemedTextView?
        private var boundsObserver: NSObjectProtocol?

        init(onChange: @escaping (String) -> Void, onScroll: ((Double) -> Void)?) {
            self.onChange = onChange
            self.onScroll = onScroll
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func observeScrolling(of scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let textView = self.textView, !textView.isProgrammaticScroll else { return }
                    self.onScroll?(textView.visibleTopLine() + 1)
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? ThemedTextView else { return }
            onChange(textView.string)
            textView.rehighlight()
        }
    }
}

/// NSTextView that colors Markdown from the theme's palette, follows light/dark switches, and
/// converts between scroll positions and document lines.
final class ThemedTextView: NSTextView {
    static let highlightingLimit = 200_000

    var palette: EditorPalette? {
        didSet { if palette != oldValue { applyStyle() } }
    }

    /// Set while `scroll(toLine:)` moves the view so the bounds change is not reported as user scrolling.
    private(set) var isProgrammaticScroll = false
    private(set) var style = EditorStyle(palette: nil, isDark: false)
    private var lineIndex = LineIndex(text: "")

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()
    }

    private func applyStyle() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        style = EditorStyle(palette: palette, isDark: isDark)
        backgroundColor = style.background
        insertionPointColor = style.foreground
        enclosingScrollView?.backgroundColor = style.background
        rehighlight()
    }

    /// Re-applies base attributes and Markdown coloring to the whole text. Attribute-only, so undo is untouched.
    func rehighlight() {
        guard let textStorage else { return }
        let text = string
        lineIndex = LineIndex(text: text)
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.setAttributes(style.baseAttributes, range: full)
        if textStorage.length <= Self.highlightingLimit {
            for span in MarkdownHighlighter.spans(in: text) where NSMaxRange(span.range) <= textStorage.length {
                textStorage.addAttributes(style.attributes(for: span.kind), range: span.range)
            }
        }
        textStorage.endEditing()
        typingAttributes = style.baseAttributes
    }

    /// 0-based logical line at the top of the visible area plus the fraction scrolled into it.
    func visibleTopLine() -> Double {
        guard let layoutManager, let textContainer, let clipView = enclosingScrollView?.contentView else { return 0 }
        let y = clipView.bounds.origin.y - textContainerInset.height
        guard y > 0, layoutManager.numberOfGlyphs > 0 else { return 0 }
        let glyphIndex = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y), in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let line = lineIndex.line(at: characterIndex)
        let rect = boundingRect(ofLine: line)
        let fraction = rect.height > 0 ? min(max((y - rect.minY) / rect.height, 0), 1) : 0
        return Double(line) + fraction
    }

    /// Scrolls so the fractional 0-based `line` sits at the top edge.
    func scroll(toLine line: Double) {
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let whole = min(max(Int(line.rounded(.down)), 0), lineIndex.count - 1)
        let rect = boundingRect(ofLine: whole)
        let fraction = min(max(line - Double(whole), 0), 1)
        var y = rect.minY + fraction * rect.height + textContainerInset.height
        let maxY = max(0, frame.height - clipView.bounds.height)
        y = min(max(y, 0), maxY)
        isProgrammaticScroll = true
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clipView)
        isProgrammaticScroll = false
    }

    private func boundingRect(ofLine line: Int) -> NSRect {
        guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else { return .zero }
        let characters = lineIndex.range(ofLine: line)
        if characters.length == 0 {
            if characters.location >= (string as NSString).length {
                return layoutManager.extraLineFragmentRect
            }
            let glyph = layoutManager.glyphIndexForCharacter(at: characters.location)
            return layoutManager.lineFragmentRect(forGlyphAt: min(glyph, layoutManager.numberOfGlyphs - 1), effectiveRange: nil)
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
    }
}
