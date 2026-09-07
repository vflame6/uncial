import AppKit
import SwiftUI
import UncialCore

/// Plain-text Markdown editor: SF Mono, soft wrap, no smart substitutions, native find bar and undo,
/// Markdown-aware coloring, optional line numbers, and scroll reporting for Live Preview sync.
struct MarkdownTextView: NSViewRepresentable {
    let text: String
    let palette: EditorPalette?
    let showsLineNumbers: Bool
    let autoPairing: Bool
    /// 1-based fractional document line to scroll to; a new token performs the scroll.
    var scrollTarget: ScrollTarget?
    /// Receives the text view so menu commands (Edit ▸ Find) can address it.
    let handle: EditorHandle
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
        textView.autoPairingEnabled = autoPairing
        textView.string = text
        textView.palette = palette
        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.rulersVisible = showsLineNumbers
        context.coordinator.textView = textView
        context.coordinator.observeScrolling(of: scrollView)
        handle.textView = textView
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
        if scrollView.rulersVisible != showsLineNumbers {
            scrollView.rulersVisible = showsLineNumbers
        }
        textView.autoPairingEnabled = autoPairing
        if textView.string != text {
            textView.replaceText(with: text)
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

/// NSTextView that colors Markdown from the theme's palette, follows light/dark switches, closes
/// pairs as you type, and converts between scroll positions and document lines.
final class ThemedTextView: NSTextView {
    static let highlightingLimit = 200_000

    var palette: EditorPalette? {
        didSet { if palette != oldValue { applyStyle() } }
    }

    /// Set while `scroll(toLine:)` moves the view so the bounds change is not reported as user scrolling.
    private(set) var isProgrammaticScroll = false
    private(set) var style = EditorStyle(palette: nil, isDark: false)
    private(set) var lineIndex = LineIndex(text: "")
    private var lineNumberView: LineNumberRulerView? { enclosingScrollView?.verticalRulerView as? LineNumberRulerView }

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

    /// Replaces the whole text after an external change (reload, another editor): caret kept in
    /// range, undo history and tracked pairs dropped.
    func replaceText(with text: String) {
        let selection = selectedRange()
        string = text
        let length = (text as NSString).length
        let location = min(selection.location, length)
        setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        undoManager?.removeAllActions()
        pairing.reset()
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
        lineNumberView?.invalidate()
    }

    // MARK: Auto-pairing

    var autoPairingEnabled = true
    private var pairing = AutoPairing()
    private var isApplyingPairEdit = false
    private var isMultiRangeChange = false

    /// The storage's own string, without copying it into a Swift String.
    private var currentText: NSString { textStorage?.mutableString ?? NSMutableString() }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard autoPairingEnabled, replacementRange.location == NSNotFound, !hasMarkedText(),
              let typed = (string as? String) ?? (string as? NSAttributedString)?.string,
              let edit = pairing.typed(typed, in: currentText, selection: selectedRange()) else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        apply(edit)
    }

    override func insertNewline(_ sender: Any?) {
        if autoPairingEnabled, !hasMarkedText(), let edit = pairing.newline(in: currentText, selection: selectedRange()) {
            apply(edit)
        } else {
            super.insertNewline(sender)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        if autoPairingEnabled, !hasMarkedText(), let edit = pairing.deleteBackward(in: currentText, selection: selectedRange()) {
            apply(edit)
        } else {
            super.deleteBackward(sender)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !isApplyingPairEdit, let range = ranges.first?.rangeValue {
            pairing.selectionChanged(to: range)
        }
    }

    /// Every character change NSTextView makes for the user (typing, paste, delete, drag, undo, find
    /// bar replace) announces its exact range here first; the text storage delegate only sees ranges
    /// widened by attribute fix-ups, which is why it is not used.
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let allowed = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if allowed, !isApplyingPairEdit, !isMultiRangeChange, let replacement = replacementString {
            pairing.textChanged(in: affectedCharRange, replacementLength: (replacement as NSString).length)
        }
        return allowed
    }

    /// A one-range call is the ordinary edit above (NSTextView nests the two); several ranges at
    /// once (Replace All) make every tracked position unreliable, so the pairs are forgotten.
    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        guard affectedRanges.count > 1 else {
            return super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
        }
        isMultiRangeChange = true
        defer { isMultiRangeChange = false }
        let allowed = super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
        if allowed {
            pairing.reset()
        }
        return allowed
    }

    /// Runs one decision through the normal, undoable insertion path with our own mapping switched off.
    private func apply(_ edit: AutoPairing.Edit) {
        isApplyingPairEdit = true
        defer { isApplyingPairEdit = false }
        if edit.range.length > 0 || !edit.replacement.isEmpty {
            insertText(edit.replacement, replacementRange: edit.range)
        }
        setSelectedRange(edit.selection)
    }

    // MARK: Scroll math

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
