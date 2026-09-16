import AppKit
import SwiftUI
import UncialCore

/// Plain-text Markdown editor: SF Mono, soft wrap, no smart substitutions, native find bar and undo,
/// Markdown-aware coloring, optional line numbers, and scroll reporting for Split View sync.
struct MarkdownTextView: NSViewRepresentable {
    let text: String
    let palette: EditorPalette?
    /// Body size in points (headings scale from it).
    let fontSize: CGFloat
    let showsLineNumbers: Bool
    let autoPairing: Bool
    let continueLists: Bool
    let presentation: EditorPresentation
    /// Center a readable column in the inline presentation.
    let readableWidth: Bool
    /// The document's directory, for relative link and image destinations.
    let baseURL: URL?
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

        // TextKit 1: NSLayoutManager gives the glyph ↔ point ↔ line math the sync needs and the
        // glyph properties the inline presentation needs.
        let textView = ThemedTextView.standalone()
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
        textView.continuesLists = continueLists
        textView.presentation = presentation
        textView.readableWidth = readableWidth
        textView.baseURL = baseURL
        textView.string = text
        textView.fontSize = fontSize
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
        textView.fontSize = fontSize
        if textView.palette != palette {
            textView.palette = palette
        }
        if scrollView.rulersVisible != showsLineNumbers {
            scrollView.rulersVisible = showsLineNumbers
        }
        textView.autoPairingEnabled = autoPairing
        textView.continuesLists = continueLists
        textView.baseURL = baseURL
        textView.readableWidth = readableWidth
        if textView.presentation != presentation {
            textView.presentation = presentation
        }
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

/// NSTextView that colors Markdown from the theme's palette (or renders it in place, see
/// `presentation`), follows light/dark switches, closes pairs as you type, and converts between
/// scroll positions and document lines.
final class ThemedTextView: NSTextView {
    static let highlightingLimit = 200_000

    /// The TextKit 1 stack the app uses: storage → `InlineLayoutManager` → container → view, with
    /// the view as the layout manager's delegate (glyph hiding) and non-contiguous layout on.
    static func standalone() -> ThemedTextView {
        let storage = NSTextStorage()
        let layoutManager = InlineLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = ThemedTextView(frame: .zero, textContainer: container)
        layoutManager.delegate = textView
        return textView
    }

    var palette: EditorPalette? {
        didSet { if palette != oldValue { applyStyle() } }
    }

    /// Body size in points; 13 is the system size.
    var fontSize: CGFloat = 13 {
        didSet { if fontSize != oldValue { applyStyle() } }
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
        style = EditorStyle(palette: palette, isDark: isDark, size: fontSize)
        backgroundColor = style.background
        insertionPointColor = style.foreground
        enclosingScrollView?.backgroundColor = style.background
        linkTextAttributes = [.foregroundColor: style.accent, .cursor: NSCursor.iBeam]
        if let layoutManager = layoutManager as? InlineLayoutManager {
            layoutManager.codeBackground = InlineStyle(style: style).codeBackground
            layoutManager.lineColor = style.muted
            layoutManager.accent = style.accent
        }
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

    /// Re-applies base attributes and, per presentation, the Markdown coloring or the inline
    /// rendering. Attribute-only, so undo is untouched. Inline: every glyph is invalidated so markers
    /// that appeared or vanished anywhere are hidden or shown correctly (regenerated lazily).
    func rehighlight() {
        guard let textStorage else { return }
        let text = string
        lineIndex = LineIndex(text: text)
        let full = NSRange(location: 0, length: textStorage.length)
        let hadMarkers = markers != .empty
        textStorage.beginEditing()
        textStorage.setAttributes(style.baseAttributes, range: full)
        if textStorage.length <= Self.highlightingLimit {
            let tokens = MarkdownHighlighter.tokens(in: text)
            switch presentation {
            case .source:
                for span in MarkdownHighlighter.spans(from: tokens) where NSMaxRange(span.range) <= textStorage.length {
                    textStorage.addAttributes(style.attributes(for: span.kind), range: span.range)
                }
                markers = .empty
            case .inline:
                let textWidth = (textContainer?.size.width ?? 0) - 2 * (textContainer?.lineFragmentPadding ?? 0)
                resolvedImages = InlineStyle(style: style).apply(tokens, to: textStorage, images: { self.image(for: $0) }, textWidth: textWidth)
                markers = MarkerIndex(tokens: tokens, resolvedImages: resolvedImages)
            }
        } else {
            markers = .empty
        }
        if presentation == .source { resolvedImages = [] }
        textStorage.endEditing()
        typingAttributes = style.baseAttributes
        if hadMarkers || markers != .empty {
            revealed = markers.revealedRange(for: selectedRange(), in: currentText)
            layoutManager?.invalidateGlyphs(forCharacterRange: full, changeInLength: 0, actualCharacterRange: nil)
            layoutManager?.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
        }
        lineNumberView?.invalidate()
    }

    // MARK: Inline presentation

    /// `.inline` renders Markdown in place and hides the markers of every line but the caret's.
    var presentation: EditorPresentation = .source {
        didSet {
            guard presentation != oldValue else { return }
            updateInsets()
            rehighlight()
        }
    }
    /// In the inline presentation, center a column of at most `InlineLayout.readableWidth`.
    var readableWidth = true {
        didSet { if readableWidth != oldValue { updateInsets() } }
    }
    /// The document's directory; relative link and image destinations resolve against it.
    var baseURL: URL? {
        didSet {
            guard baseURL != oldValue else { return }
            imageCache.removeAll()
            if presentation == .inline { rehighlight() }
        }
    }
    private(set) var markers = MarkerIndex.empty
    /// Locations of the image tokens that loaded and are drawn under their paragraph.
    private(set) var resolvedImages: Set<Int> = []
    private var imageCache: [String: NSImage?] = [:]
    private var pendingImages: Set<String> = []
    /// Fetches a remote image and calls back on the main thread; tests inject their own.
    var remoteImageLoader: (URL, @escaping (NSImage?) -> Void) -> Void = { url, completion in
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
    private var layoutWidth: CGFloat = 0
    /// The paragraphs (or fenced block) whose markers are shown because the selection touches them.
    private(set) var revealed = NSRange(location: 0, length: 0) {
        didSet { (layoutManager as? InlineLayoutManager)?.revealed = revealed }
    }
    private var bulletCache: (font: NSFont, glyph: CGGlyph?)?

    private func updateReveal() {
        guard presentation == .inline, markers != .empty, let layoutManager else { return }
        let next = markers.revealedRange(for: selectedRange(), in: currentText)
        guard next != revealed else { return }
        let previous = revealed
        revealed = next
        let whole = NSRange(location: 0, length: currentText.length)
        for range in [previous, next] {
            let clamped = NSIntersectionRange(range, whole)
            guard clamped.length > 0 else { continue }
            layoutManager.invalidateGlyphs(forCharacterRange: clamped, changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: clamped, actualCharacterRange: nil)
        }
    }

    /// Local images load right away; http(s) ones are fetched once through `remoteImageLoader`
    /// and, once here, re-render the text. Every outcome is cached per destination, misses too.
    func image(for destination: String) -> NSImage? {
        if let cached = imageCache[destination] { return cached }
        let url = URL(string: destination, relativeTo: baseURL)?.absoluteURL ?? baseURL?.appendingPathComponent(destination)
        guard let url else {
            imageCache[destination] = .some(nil)
            return nil
        }
        if url.isFileURL {
            let loaded = NSImage(contentsOf: url)
            imageCache[destination] = .some(loaded)
            return loaded
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !pendingImages.contains(destination) else {
            if !url.isFileURL, !pendingImages.contains(destination) { imageCache[destination] = .some(nil) }
            return nil
        }
        pendingImages.insert(destination)
        remoteImageLoader(url) { [weak self] image in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingImages.remove(destination)
                self.imageCache[destination] = .some(image)
                if image != nil, self.presentation == .inline {
                    self.rehighlight()
                }
            }
        }
        return nil
    }

    /// The column follows the width, and images are fitted to the text width, so a width change
    /// re-fits both.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard newSize.width != layoutWidth else { return }
        layoutWidth = newSize.width
        updateInsets()
        if presentation == .inline, !resolvedImages.isEmpty {
            rehighlight()
        }
    }

    private func updateInsets() {
        let inset = presentation == .inline && readableWidth ? InlineLayout.horizontalInset(viewWidth: bounds.width) : 16
        if textContainerInset.width != inset {
            textContainerInset = NSSize(width: inset, height: textContainerInset.height)
        }
    }

    /// The bullet glyph of `font`, if it has one.
    private func bulletGlyph(for font: NSFont) -> CGGlyph? {
        if let bulletCache, bulletCache.font == font { return bulletCache.glyph }
        var character: UniChar = 0x2022
        var glyph = CGGlyph(0)
        let found = CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1)
        bulletCache = (font, found ? glyph : nil)
        return bulletCache?.glyph
    }

    /// A click on a drawn task box toggles it instead of moving the caret.
    override func mouseDown(with event: NSEvent) {
        if presentation == .inline, let box = taskBox(at: convert(event.locationInWindow, from: nil)) {
            toggle(taskBox: box)
            return
        }
        super.mouseDown(with: event)
    }

    /// The `[ ]` under `point` (view coordinates) while its brackets are hidden; nil on revealed lines.
    func taskBox(at point: NSPoint) -> NSRange? {
        guard presentation == .inline, let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = layoutManager.characterIndex(for: local, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < textStorage.length else { return nil }
        var box = NSRange()
        let whole = NSRange(location: 0, length: textStorage.length)
        guard textStorage.attribute(.taskBox, at: index, longestEffectiveRange: &box, in: whole) != nil,
              box.length == 3, !NSLocationInRange(box.location, revealed) else { return nil }
        return box
    }

    /// Flips `[ ]`/`[x]` through the undoable change path; the caret stays where it is.
    func toggle(taskBox box: NSRange) {
        guard let textStorage, box.length == 3 else { return }
        let middle = NSRange(location: box.location + 1, length: 1)
        let replacement = currentText.character(at: middle.location) == 0x20 ? "x" : " "
        guard shouldChangeText(in: middle, replacementString: replacement) else { return }
        textStorage.replaceCharacters(in: middle, with: replacement)
        didChangeText()
    }

    /// Plain click: put the caret there, which reveals the line. ⌘-click: open the destination.
    override func clicked(onLink link: Any, at charIndex: Int) {
        let destination = (link as? String) ?? (link as? URL)?.absoluteString ?? ""
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true, !destination.hasPrefix("#"),
           let url = URL(string: destination, relativeTo: baseURL)?.absoluteURL {
            LinkOpener.open(url)
        } else {
            setSelectedRange(NSRange(location: charIndex, length: 0))
        }
    }

    // MARK: Undo

    /// The editor's own undo manager. Registering edits with the window's (NSDocument's) manager made
    /// the document count changes, autosave its stale copy and complain about the model's own writes.
    private let editorUndoManager = UndoManager()

    override var undoManager: UndoManager? { editorUndoManager }

    @objc func undo(_ sender: Any?) {
        editorUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        editorUndoManager.redo()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): editorUndoManager.canUndo
        case #selector(redo(_:)): editorUndoManager.canRedo
        default: super.validateUserInterfaceItem(item)
        }
    }

    // MARK: Auto-pairing

    var autoPairingEnabled = true
    var continuesLists = true
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
        guard !hasMarkedText(), selectedRange().length == 0 else {
            super.insertNewline(sender)
            return
        }
        if autoPairingEnabled, let edit = pairing.newline(in: currentText, selection: selectedRange()) {
            apply(edit)
        } else if continuesLists, let edit = ListContinuation.edit(in: currentText, at: selectedRange().location) {
            pairing.textChanged(in: edit.range, replacementLength: (edit.replacement as NSString).length)
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
        updateReveal()
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

extension ThemedTextView: NSLayoutManagerDelegate {
    /// Hides markers outside the revealed range (zero-width `.null` glyphs) and re-glyphs list
    /// bullets. Works only from the arrays it is handed: any glyph-tree query here throws
    /// "reentrant glyph generation problem" (probed 2026-09-15).
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard presentation == .inline, glyphRange.length > 0 else { return 0 }
        let count = glyphRange.length
        let first = characterIndexes[0]
        let span = NSRange(location: first, length: characterIndexes[count - 1] - first + 1)
        let wantsBullet = markers.bullets.contains { NSLocationInRange($0, span) }
        guard markers.hasHidden(in: span) || wantsBullet else { return 0 }
        let bullet = wantsBullet ? bulletGlyph(for: font) : nil
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
        var newProperties = Array(UnsafeBufferPointer(start: properties, count: count))
        for index in 0..<count {
            let character = characterIndexes[index]
            if markers.isHidden(character), !NSLocationInRange(character, revealed) {
                newProperties[index] = .null
            } else if let bullet, markers.bullets.contains(character) {
                newGlyphs[index] = bullet
            }
        }
        layoutManager.setGlyphs(newGlyphs, properties: newProperties, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return count
    }
}
