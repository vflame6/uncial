import AppKit
import SwiftUI
import UncialCore

/// Plain-text Markdown editor: SF Mono, soft wrap, no smart substitutions, native find bar and undo,
/// Markdown-aware coloring, optional line numbers, and scroll reporting for Split View sync.
struct MarkdownTextView: NSViewRepresentable {
    let text: String
    /// Colors, fonts and the cache key of the diagrams drawn in Live Preview.
    let theme: Theme
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
    /// Whether http(s) images are fetched for Live Preview (`AppSettings.loadRemoteContent`).
    let loadsRemoteImages: Bool
    /// Where a local image or linked file is looked for when it is not where the document says.
    let attachmentSearch: AttachmentSearch
    /// Where a pasted or dropped file is put (`AppSettings.attachmentDestination`).
    let attachmentDestination: AttachmentImporter.Destination
    /// 1-based fractional document line to scroll to; a new token performs the scroll.
    var scrollTarget: ScrollTarget?
    /// Receives the text view so menu commands (Edit ▸ Find) can address it.
    let handle: EditorHandle
    let onChange: (String) -> Void
    /// Called with the 1-based fractional line at the top of the visible area when the user scrolls.
    var onScroll: ((Double) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange, onScroll: onScroll) }

    /// The editor's views as the app builds them: a `ThemedTextView` (TextKit 1: `NSLayoutManager` gives
    /// the glyph ↔ point ↔ line math the sync needs and the glyph properties the inline presentation
    /// needs) as the document of a scroll view, with the line-number ruler; text and settings come after.
    static func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

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
        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView, scrollView: scrollView)
        return scrollView
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = Self.makeScrollView()
        guard let textView = scrollView.documentView as? ThemedTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.autoPairingEnabled = autoPairing
        textView.continuesLists = continueLists
        textView.presentation = presentation
        textView.readableWidth = readableWidth
        textView.baseURL = baseURL
        textView.loadsRemoteImages = loadsRemoteImages
        textView.attachmentSearch = attachmentSearch
        textView.attachmentDestination = attachmentDestination
        textView.theme = theme
        textView.string = text
        textView.fontSize = fontSize
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
        if scrollView.rulersVisible != showsLineNumbers {
            scrollView.rulersVisible = showsLineNumbers
        }
        textView.autoPairingEnabled = autoPairing
        textView.continuesLists = continueLists
        textView.baseURL = baseURL
        textView.loadsRemoteImages = loadsRemoteImages
        textView.attachmentSearch = attachmentSearch
        textView.attachmentDestination = attachmentDestination
        textView.theme = theme
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
        layoutManager.willDrawPicture = { [weak textView] in textView?.pictures.willDraw($0) }
        textView.pictures.onLoad = { [weak textView] in
            guard let textView else { return }
            textView.setNeedsDisplay(textView.visibleRect)
        }
        textView.registerForDraggedTypes(textView.readablePasteboardTypes)
        return textView
    }

    /// Body size in points; 13 is the system size.
    var fontSize: CGFloat = 13 {
        didSet { if fontSize != oldValue { applyStyle() } }
    }

    /// Set while `scroll(toLine:)` moves the view so the bounds change is not reported as user scrolling.
    private(set) var isProgrammaticScroll = false
    private(set) var style = EditorStyle(theme: .default, isDark: false)
    /// Set while `rehighlight()` runs: a selection change it causes must not start another pass.
    private var isRehighlighting = false
    /// Set while `replaceText(with:)` swaps the string; its own pass settles the reveal.
    private var isReplacingText = false
    private(set) var lineIndex = LineIndex(text: "")
    private var lineNumberView: LineNumberRulerView? { enclosingScrollView?.verticalRulerView as? LineNumberRulerView }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // NSTextView registers its own drag types on the way into a window; ours must be there too.
        registerForDraggedTypes(readablePasteboardTypes)
        applyStyle()
    }

    private func applyStyle() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        style = EditorStyle(theme: theme, isDark: isDark, size: fontSize)
        backgroundColor = style.background
        insertionPointColor = style.foreground
        enclosingScrollView?.backgroundColor = style.background
        linkTextAttributes = [.foregroundColor: style.accent, .cursor: NSCursor.iBeam]
        if let layoutManager = layoutManager as? InlineLayoutManager {
            layoutManager.codeBackground = InlineStyle(style: style).codeBackground
            layoutManager.revealBackground = InlineStyle(style: style).revealBackground
            layoutManager.revealPadding = InlineStyle.revealPadding * style.scale
            layoutManager.lineColor = style.muted
            layoutManager.accent = style.accent
            layoutManager.separatorColor = style.muted.withAlphaComponent(0.35)
            layoutManager.calloutColors = Dictionary(uniqueKeysWithValues: Callouts.Role.allCases.map { ($0, style.calloutColor(for: $0)) })
            layoutManager.calloutTitleFont = style.calloutTitleFont
            layoutManager.calloutIconSize = InlineStyle.calloutIconSize * style.scale
        }
        rehighlight()
    }

    /// Replaces the whole text after an external change (reload, another editor): caret kept in
    /// range, undo history and tracked pairs dropped. The old markers describe the old text, so
    /// they go first, and the reveal waits for the pass at the end.
    func replaceText(with text: String) {
        let selection = selectedRange()
        markers = .empty
        isReplacingText = true
        string = text
        let length = (text as NSString).length
        let location = min(selection.location, length)
        setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        isReplacingText = false
        undoManager?.removeAllActions()
        pairing.reset()
        rehighlight()
    }

    /// Styles the text again: the Markdown coloring or, in the inline presentation, the rendered look
    /// outside the revealed lines and the source look inside them, then the code inside fenced blocks
    /// (`CodeSyntaxStyle`). Attribute-only, so undo is untouched.
    ///
    /// The look is worked out on a copy and only the lines where it differs change in the text
    /// (`AttributeDifference`): the layout manager lays out again what the storage reports as edited,
    /// and it estimates the positions of text it has not laid out. A pass that rewrote every attribute
    /// (every keystroke, every caret move to another paragraph) left the whole document on such
    /// estimates: the arrow keys picked their line from them and went back up or skipped lines, the
    /// view scrolled thousands of points, and the document's height was a fraction of the real one.
    func rehighlight() {
        guard let textStorage, !isRehighlighting else { return }
        passes += 1
        isRehighlighting = true
        defer { isRehighlighting = false }
        let text = string
        let length = textStorage.length
        let reading = read(text, length: length)
        let target = NSTextStorage(string: text, attributes: style.baseAttributes)
        var found = InlineStyle.Resolved()
        var foundMarkers = MarkerIndex.empty
        var reveal = NSRange(location: 0, length: 0)
        if let reading {
            target.beginEditing()
            switch presentation {
            case .source:
                for span in MarkdownHighlighter.spans(from: reading.tokens) where NSMaxRange(span.range) <= length {
                    target.addAttributes(style.attributes(for: span.kind), range: span.range)
                }
            case .inline:
                // A diagram or formula the caret is in stays source, so the reveal is settled first, from the new tokens.
                reveal = reading.blocks.revealedRange(for: selectedRange(), in: reading.text)
                found = InlineStyle(style: style).apply(reading.tokens, to: target, images: { self.image(for: $0) },
                                                        loadedImages: { self.loadedImage(for: $0) }, diagrams: { self.image(forDiagram: $0) },
                                                        math: { self.picture(forMath: $0, display: $1) }, revealed: reveal, textWidth: textWidth)
                foundMarkers = MarkerIndex(tokens: reading.tokens, resolvedImages: found.images, resolvedDiagrams: found.diagrams,
                                           resolvedMath: found.math, calloutBlocks: reading.callouts)
            }
            CodeSyntaxStyle.apply(reading.tokens, to: target, style: style)
            Self.markGlyphs(of: foundMarkers, revealed: reveal, in: target)
            target.endEditing()
        }
        let changed = AttributeDifference.lines(of: textStorage, differingFrom: target, lines: lineIndex)
        // What an edit changed TextKit has laid out again already, from the edit on.
        let edited = (layoutManager as? InlineLayoutManager)?.takeEditedRange()
        // Before the text changes: the glyphs made for it read these.
        markers = foundMarkers
        revealed = reveal
        resolvedImages = found.images
        resolvedDiagrams = found.diagrams
        resolvedMath = found.math
        literalBlocks = reading?.literalBlocks ?? []
        adopt(target, in: changed)
        typingAttributes = style.baseAttributes
        invalidate(Self.joined(changed + [edited ?? NSRange(location: 0, length: 0)]))
        completeLayout()
        lineNumberView?.invalidate()
    }

    /// What a pass reads from the text; kept while the text stays the same, so that a pass after a
    /// picture landed, the width changed or the caret moved does not read it again (tokenizing is
    /// more than half of a pass).
    private struct Reading {
        let text: NSString
        let tokens: [MarkdownHighlighter.Token]
        let callouts: [NSRange]
        let literalBlocks: [NSRange]
        /// The blocks that reveal as a whole, whatever pictures are drawn.
        let blocks: MarkerIndex
        /// Fenced code as `CodeSyntaxStyle` pairs it, a fence with the next fence, in order.
        let codeBlocks: [NSRange]
    }

    private var reading: Reading?

    /// The reading of `text`, nil above the highlighting limit; `lineIndex` follows the text here.
    private func read(_ text: String, length: Int) -> Reading? {
        guard length <= Self.highlightingLimit else {
            reading = nil
            lineIndex = LineIndex(text: text)
            return nil
        }
        if let reading, reading.text.isEqual(to: text) { return reading }
        lineIndex = LineIndex(text: text)
        let tokens = MarkdownHighlighter.tokens(in: text)
        let source = text as NSString
        let callouts = MarkdownHighlighter.calloutBlocks(in: tokens, text: source).map(\.range)
        let fresh = Reading(text: source, tokens: tokens, callouts: callouts, literalBlocks: MarkdownHighlighter.literalBlocks(in: tokens),
                            blocks: MarkerIndex(tokens: tokens, calloutBlocks: callouts), codeBlocks: Self.codeBlocks(in: tokens))
        reading = fresh
        return fresh
    }

    /// Every fenced code block from its opening fence to its closing one, or to its last line of code
    /// when it is not closed.
    private static func codeBlocks(in tokens: [MarkdownHighlighter.Token]) -> [NSRange] {
        var blocks: [NSRange] = []
        var start: Int?
        var end = 0
        for token in tokens {
            switch token.kind {
            case .fence:
                if let opening = start {
                    blocks.append(NSRange(location: opening, length: NSMaxRange(token.range) - opening))
                    start = nil
                } else {
                    start = token.range.location
                    end = NSMaxRange(token.range)
                }
            case .code where start != nil:
                end = NSMaxRange(token.range)
            default:
                break
            }
        }
        if let opening = start {
            blocks.append(NSRange(location: opening, length: end - opening))
        }
        return blocks
    }

    /// The room for text in a line, which bounds the pictures.
    private var textWidth: CGFloat {
        (textContainer?.size.width ?? 0) - 2 * (textContainer?.lineFragmentPadding ?? 0)
    }

    /// Writes into the text's look what the glyphs and the layout do with it: the markers hidden
    /// outside `revealed` (`.hiddenMarker`), the list markers drawn as bullets (`.listBullet`) and where
    /// the revealed lines start and end (`.revealStart`, `.revealEnd`; within `range` when only that
    /// part is styled). The delegate
    /// methods at the end of this file read nothing else, so they are right for a text that was edited
    /// and not styled yet: TextKit makes glyphs and lines again as soon as a character changes, before
    /// `textDidChange`, and `markers` and `revealed` then still count in the text before the edit.
    private static func markGlyphs(of markers: MarkerIndex, revealed: NSRange, in storage: NSTextStorage, within range: NSRange? = nil) {
        let length = storage.length
        for hidden in markers.hidden where NSMaxRange(hidden) <= length {
            for part in InlineStyle.complement(of: revealed, in: hidden) where part.length > 0 {
                storage.addAttribute(.hiddenMarker, value: true, range: part)
            }
        }
        for bullet in markers.bullets where bullet < length {
            storage.addAttribute(.listBullet, value: true, range: NSRange(location: bullet, length: 1))
        }
        let whole = range ?? NSRange(location: 0, length: length)
        guard revealed.length > 0, NSMaxRange(revealed) <= length else { return }
        if NSLocationInRange(revealed.location, whole) {
            storage.addAttribute(.revealStart, value: true, range: NSRange(location: revealed.location, length: 1))
        }
        if NSLocationInRange(NSMaxRange(revealed) - 1, whole) {
            storage.addAttribute(.revealEnd, value: true, range: NSRange(location: NSMaxRange(revealed) - 1, length: 1))
        }
    }

    /// More changed stretches than this are taken as one: each is an edit of its own to the storage.
    private static let separateEdits = 64

    /// Gives the text `target`'s attributes over `ranges`, each stretch as an edit of its own, so that
    /// the layout manager lays those out again and nothing between them.
    private func adopt(_ target: NSAttributedString, in ranges: [NSRange]) {
        guard let textStorage, let first = ranges.first, let last = ranges.last else { return }
        let edits = ranges.count > Self.separateEdits ? [NSUnionRange(first, last)] : ranges
        for range in edits {
            textStorage.beginEditing()
            target.enumerateAttributes(in: range, options: .longestEffectiveRangeNotRequired) { attributes, run, _ in
                textStorage.setAttributes(attributes, range: run)
            }
            textStorage.endEditing()
        }
    }

    /// Has the glyphs and the layout of `ranges` made again, each between two places where a layout
    /// of the whole text starts a line too. The hidden markers a paragraph starts with belong to the
    /// last line of the paragraph before, which for that keeps no room under it (a heading's divider)
    /// and whose line they would otherwise start; and TextKit lays out again from the first glyph it
    /// is told of. Begun at a paragraph that starts hidden, the layout gave it a line of its own start
    /// (with the room a callout's title keeps above it); begun at one that just stopped starting
    /// hidden, it left the paragraph before as it was with those markers. So a stretch starts a
    /// paragraph early, further back while that one begins with a hidden marker, and ends after the
    /// hidden markers that follow it.
    private func invalidate(_ ranges: [NSRange]) {
        guard let layoutManager, let textStorage else { return }
        let text = textStorage.mutableString
        func isHidden(_ index: Int, _ run: NSRangePointer? = nil) -> Bool {
            textStorage.attribute(.hiddenMarker, at: index, effectiveRange: run) != nil
        }
        func paragraphStart(before location: Int) -> Int {
            location > 0 ? text.paragraphRange(for: NSRange(location: location - 1, length: 0)).location : 0
        }
        for range in ranges where range.length > 0 && NSMaxRange(range) <= text.length {
            var start = paragraphStart(before: text.paragraphRange(for: NSRange(location: range.location, length: 0)).location)
            while start > 0, isHidden(start) {
                start = paragraphStart(before: start)
            }
            var end = NSMaxRange(text.paragraphRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0)))
            var run = NSRange()
            while end < text.length, isHidden(end, &run) {
                end = NSMaxRange(run)
            }
            let extended = NSRange(location: start, length: end - start)
            layoutManager.invalidateGlyphs(forCharacterRange: extended, changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: extended, actualCharacterRange: nil)
        }
    }

    /// A text narrower than this is not laid out whole: the view has no width yet when the text goes
    /// in, and a line per character is a long layout.
    private static let narrowestLayout: CGFloat = 100

    /// Lays out whatever is not laid out, so that every position and the document's height are exact:
    /// TextKit estimates the positions of text it has not laid out, far off for Markdown (a quarter
    /// of the real height for a note of 4,800 lines), and corrects them as the view scrolls there.
    /// With every pass keeping the layout it does not change, this is a fraction of a millisecond
    /// but for a new text, a new look or a new width. Not while the width is still changing, and not
    /// above the highlighting limit, where the text is plain and may be very long.
    private func completeLayout() {
        guard let layoutManager, let textContainer, let textStorage, !inLiveResize, !isSettingWidth else { return }
        awaitsLayout = false
        guard textStorage.length <= Self.highlightingLimit, textContainer.size.width >= Self.narrowestLayout else { return }
        layoutManager.ensureLayout(for: textContainer)
    }

    /// How long the width has to stay the same before the text is laid out whole again.
    static let layoutSettleDelay: TimeInterval = 0.05

    /// A new width leaves all of the text to lay out again: once the width has settled, not at every
    /// step of an animated resize.
    private func scheduleLayoutCompletion() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(completeLayoutOnceSettled), object: nil)
        perform(#selector(completeLayoutOnceSettled), with: nil, afterDelay: Self.layoutSettleDelay)
    }

    @objc private func completeLayoutOnceSettled() {
        completeLayout()
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
        didSet {
            guard readableWidth != oldValue else { return }
            updateInsets()
            // The text width changed: pictures are fitted again, as after a resize (BUG-22).
            refitPictures()
        }
    }
    /// The document's directory; relative link and image destinations resolve against it.
    var baseURL: URL? {
        didSet {
            guard baseURL != oldValue else { return }
            forgetImages()
            if presentation == .inline { rehighlight() }
        }
    }
    /// Whether http(s) image destinations are fetched (`AppSettings.loadRemoteContent`); off, they
    /// stay source in Live Preview, like a file that is missing.
    var loadsRemoteImages = false {
        didSet {
            guard loadsRemoteImages != oldValue else { return }
            forgetImages()
            if presentation == .inline { rehighlight() }
        }
    }
    /// Where a local image or link destination is looked for when nothing is at the place it names
    /// (`AppSettings.attachmentSearch`): the attachments folder next to the document, its parents.
    var attachmentSearch: AttachmentSearch = .direct {
        didSet {
            guard attachmentSearch != oldValue else { return }
            forgetImages()
            if presentation == .inline { rehighlight() }
        }
    }
    /// Where a pasted or dropped file is put (`AppSettings.attachmentDestination`), together with
    /// `attachmentSearch`'s folder name and walk.
    var attachmentDestination: AttachmentImporter.Destination = .attachmentsFolder
    private(set) var markers = MarkerIndex.empty
    /// Locations of the image tokens that loaded and are drawn under their paragraph.
    private(set) var resolvedImages: Set<Int> = []
    private var imageCache: [String: NSImage?] = [:]
    private var pendingImages: Set<String> = []
    /// The pictures of local image files: sized at once, their bitmaps decoded in the background.
    private let pictures = LocalPictures()

    /// Another folder, another search or another policy: every destination is looked up again.
    private func forgetImages() {
        imageCache.removeAll()
        pictures.removeAll()
    }
    /// Fetches a remote image, within `RemoteImageLoader`'s bounds, and calls back on the main thread;
    /// tests inject their own.
    var remoteImageLoader: (URL, @escaping (NSImage?) -> Void) -> Void = { url, completion in
        RemoteImageLoader.shared.load(url, completion: completion)
    }
    /// The document theme: the colors of highlighted code and of the diagrams mermaid.js draws (part
    /// of their cache key).
    var theme: Theme = .default {
        didSet { if theme != oldValue { applyStyle() } }
    }
    /// Opening fence locations of the mermaid blocks drawn as pictures.
    private(set) var resolvedDiagrams: Set<Int> = []
    private var diagramCache: [DiagramRequest: NSImage?] = [:]
    private var pendingDiagrams: Set<DiagramRequest> = []
    /// Draws one diagram to a bitmap and calls back on the main thread; tests inject their own.
    var diagramRenderer: (DiagramRequest, @escaping (NSImage?) -> Void) -> Void = { request, completion in
        Task { @MainActor in
            completion(await DiagramWebRenderer.shared.image(for: request))
        }
    }
    /// The formulas drawn as pictures: token or block start → the character that stands for the picture.
    private(set) var resolvedMath: [Int: Int] = [:]
    private var mathCache: [MathRequest: MathPicture?] = [:]
    private var pendingMath: Set<MathRequest> = []
    private var rehighlightScheduled = false
    /// Draws one formula to a bitmap and calls back on the main thread; tests inject their own.
    var mathRenderer: (MathRequest, @escaping (MathPicture?) -> Void) -> Void = { request, completion in
        Task { @MainActor in
            completion(await DiagramWebRenderer.shared.picture(for: request))
        }
    }
    private var layoutWidth: CGFloat = 0
    /// Set while a new width is taken in: the pass that re-fits the pictures leaves the layout to
    /// `scheduleLayoutCompletion()`.
    private var isSettingWidth = false
    /// Set from a change of width until the text is laid out whole at it (`completeLayout()`).
    private var awaitsLayout = false
    /// The paragraphs (or fenced block) whose markers are shown because the selection touches them.
    private(set) var revealed = NSRange(location: 0, length: 0) {
        didSet {
            (layoutManager as? InlineLayoutManager)?.revealed = revealed
            // The band behind the revealed lines moves with them; repaint rather than rely on the layout pass.
            if revealed != oldValue { setNeedsDisplay(visibleRect) }
        }
    }
    private var bulletCache: (font: NSFont, glyph: CGGlyph?)?

    /// The raw look follows the caret: when it enters another paragraph, the paragraph it left goes
    /// back to the rendered look and the new one to the source look. Not while a drag is still
    /// selecting, and not while the storage is still processing an edit: the layout manager moves
    /// the selection from inside that, when `markers` still describe the text before it, and
    /// `textDidChange`'s pass follows anyway.
    private func updateReveal(stillSelecting: Bool = false) {
        guard presentation == .inline, !stillSelecting, !isRehighlighting, !isReplacingText, let textStorage,
              textStorage.editedMask.isEmpty, textStorage.length <= Self.highlightingLimit else { return }
        let next = markers.revealedRange(for: selectedRange(), in: currentText)
        guard next != revealed else { return }
        // The reading describes the text before an edit that has not reached `textDidChange` yet.
        guard let reading, reading.text.isEqual(currentText) else {
            rehighlight()
            return
        }
        moveReveal(to: next, reading: reading)
    }

    /// Moves the reveal by styling again the lines it leaves and the lines it enters, and nothing
    /// else: the rest of the text keeps its look and its layout, so the caret's next line is where
    /// the layout says and the view stays where it is. The look is the one a whole pass gives
    /// (`ThemedTextViewLayoutTests.movingTheCaretStylesLikeAWholePass`).
    private func moveReveal(to next: NSRange, reading: Reading) {
        guard let textStorage else { return }
        isRehighlighting = true
        defer { isRehighlighting = false }
        let ranges = Self.joined([styledLines(around: revealed, reading: reading), styledLines(around: next, reading: reading)])
        revealed = next
        var found = InlineStyle.Resolved(images: resolvedImages, diagrams: resolvedDiagrams, math: resolvedMath)
        let inline = InlineStyle(style: style)
        for range in ranges {
            let tokens = Array(reading.tokens[Self.tokens(of: reading.tokens, startingIn: range)])
            textStorage.beginEditing()
            textStorage.setAttributes(style.baseAttributes, range: range)
            let part = inline.apply(tokens, to: textStorage, images: { self.image(for: $0) }, loadedImages: { self.loadedImage(for: $0) },
                                    diagrams: { self.image(forDiagram: $0) }, math: { self.picture(forMath: $0, display: $1) },
                                    revealed: next, textWidth: textWidth, range: range)
            CodeSyntaxStyle.apply(tokens, to: textStorage, style: style)
            Self.markGlyphs(of: MarkerIndex(tokens: tokens, resolvedImages: part.images, resolvedDiagrams: part.diagrams, resolvedMath: part.math),
                            revealed: next, in: textStorage, within: range)
            textStorage.endEditing()
            found.images = found.images.filter { !NSLocationInRange($0, range) }.union(part.images)
            found.diagrams = found.diagrams.filter { !NSLocationInRange($0, range) }.union(part.diagrams)
            found.math = found.math.filter { !NSLocationInRange($0.key, range) }.merging(part.math) { $1 }
        }
        resolvedImages = found.images
        resolvedDiagrams = found.diagrams
        resolvedMath = found.math
        markers = MarkerIndex(tokens: reading.tokens, resolvedImages: found.images, resolvedDiagrams: found.diagrams,
                              resolvedMath: found.math, calloutBlocks: reading.callouts)
        typingAttributes = style.baseAttributes
        invalidate(ranges)
        completeLayout()
        lineNumberView?.invalidate()
    }

    /// The lines to style again when the reveal covers or uncovers `range`: its paragraphs; the whole
    /// of a fenced code block, whose colors come from its fence; and, for a table row, the whole table,
    /// since a row's padding comes from every row's width. The blocks that reveal as one are whole in
    /// `range` already (`MarkerIndex.revealedRange`), but they pair a fence with a `$$` line as well as
    /// with a fence, so under a `$$` that is not closed they are not the code blocks.
    private func styledLines(around range: NSRange, reading: Reading) -> NSRange {
        let text = reading.text
        let clipped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard clipped.length > 0 else { return NSRange(location: min(range.location, text.length), length: 0) }
        var lines = text.paragraphRange(for: clipped)
        for block in reading.codeBlocks where block.location < NSMaxRange(lines) && NSIntersectionRange(block, lines).length > 0 {
            lines = NSUnionRange(lines, text.lineRange(for: block))
        }
        func isTableLine(at location: Int) -> Bool {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            guard let first = Self.tokens(of: reading.tokens, startingIn: line).first else { return false }
            switch reading.tokens[first].kind {
            case .tableRow, .tableDelimiter: return true
            default: return false
            }
        }
        if isTableLine(at: lines.location) {
            while lines.location > 0, isTableLine(at: lines.location - 1) {
                lines = NSUnionRange(text.lineRange(for: NSRange(location: lines.location - 1, length: 0)), lines)
            }
        }
        if isTableLine(at: NSMaxRange(lines) - 1) {
            while NSMaxRange(lines) < text.length, isTableLine(at: NSMaxRange(lines)) {
                lines = NSUnionRange(lines, text.lineRange(for: NSRange(location: NSMaxRange(lines), length: 0)))
            }
        }
        return lines
    }

    /// The indexes of the tokens that start in `lines`, whole lines of the text: the tokens come line
    /// by line in the text's order (within a line in no order), so they are one run.
    private static func tokens(of tokens: [MarkdownHighlighter.Token], startingIn lines: NSRange) -> Range<Int> {
        func firstIndex(at location: Int) -> Int {
            var low = 0
            var high = tokens.count
            while low < high {
                let mid = (low + high) / 2
                if tokens[mid].range.location < location {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            return low
        }
        let lower = firstIndex(at: lines.location)
        return lower..<max(lower, firstIndex(at: NSMaxRange(lines)))
    }

    /// `ranges` in order, without the empty ones, those that overlap or touch as one.
    private static func joined(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.filter({ $0.length > 0 }).sorted(by: { $0.location < $1.location }) {
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Local images are here right away, as far as the layout goes (found through `attachmentSearch`
    /// when they are not where the destination says): their size is, and `LocalPictures` brings the
    /// bitmap. http(s) ones are fetched once through `remoteImageLoader` (only with `loadsRemoteImages`)
    /// and, once here, re-render the text. Every outcome is cached per destination, misses too.
    func image(for destination: String) -> NSImage? {
        if let cached = imageCache[destination] { return cached }
        let url = URL(string: destination, relativeTo: baseURL)?.absoluteURL ?? baseURL?.appendingPathComponent(destination)
        guard let url else {
            imageCache[destination] = .some(nil)
            return nil
        }
        if url.isFileURL {
            let located = baseURL.flatMap { attachmentSearch.locate(url, from: $0) } ?? url
            let loaded = pictures.picture(at: located)
            imageCache[destination] = .some(loaded)
            return loaded
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), loadsRemoteImages, !pendingImages.contains(destination) else {
            if !url.isFileURL, !pendingImages.contains(destination) { imageCache[destination] = .some(nil) }
            return nil
        }
        pendingImages.insert(destination)
        remoteImageLoader(url) { [weak self] image in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingImages.remove(destination)
                self.imageCache[destination] = .some(image)
                // Pictures that land together share one pass (each ran a whole one, PERF-2).
                if image != nil, self.presentation == .inline {
                    self.scheduleRehighlight()
                }
            }
        }
        return nil
    }

    /// The picture for `destination` that asks nothing of the web: the one already here, or a file's.
    /// It is what the caret's own paragraph shows, where a destination may be half typed.
    private func loadedImage(for destination: String) -> NSImage? {
        if let cached = imageCache[destination] { return cached }
        let url = URL(string: destination, relativeTo: baseURL)?.absoluteURL ?? baseURL?.appendingPathComponent(destination)
        return url?.isFileURL == true ? image(for: destination) : nil
    }

    /// Diagram pictures are drawn for text widths in steps of this many points, so a resize asks
    /// for few of them; `InlineStyle.reserveDiagrams` scales a picture down to the text width.
    static let diagramWidthStep: CGFloat = 32

    /// A diagram in one look, whatever the width.
    private struct DiagramLook: Hashable {
        let source: String
        let theme: Theme
        let dark: Bool
        let scale: CGFloat

        init(_ request: DiagramRequest) {
            source = request.source
            theme = request.theme
            dark = request.dark
            scale = request.scale
        }
    }

    /// The last picture drawn of each diagram, shown while one for a new width is on its way.
    private var latestDiagrams: [DiagramLook: NSImage] = [:]

    /// A diagram's picture in the current look, once `diagramRenderer` has drawn it; the first call
    /// starts the drawing and re-renders the text when it lands (one pass however many land
    /// together). Meanwhile, and during a live resize, the picture drawn for another width stands
    /// in. Every outcome is cached, misses too, one width per diagram.
    func image(forDiagram source: String) -> NSImage? {
        let room = (textContainer?.size.width ?? 0) - 2 * (textContainer?.lineFragmentPadding ?? 0)
        let width = max(Self.diagramWidthStep, (room / Self.diagramWidthStep).rounded(.down) * Self.diagramWidthStep)
        let request = DiagramRequest(source: source, theme: theme, dark: style.isDark, scale: style.scale, width: width)
        if let cached = diagramCache[request] { return cached }
        let look = DiagramLook(request)
        let latest = latestDiagrams[look]
        if inLiveResize, latest != nil { return latest }
        guard !pendingDiagrams.contains(request) else { return latest }
        pendingDiagrams.insert(request)
        diagramRenderer(request) { [weak self] image in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingDiagrams.remove(request)
                self.diagramCache = self.diagramCache.filter { DiagramLook($0.key) != look }
                self.diagramCache[request] = .some(image)
                if let image { self.latestDiagrams[look] = image }
                if image != nil, self.presentation == .inline {
                    self.scheduleRehighlight()
                }
            }
        }
        return latest
    }

    /// Pictures stood in at the old width while the window was resized; the new width's are drawn now,
    /// and the text, laid out only where it showed during the resize, is laid out whole.
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        if presentation == .inline, !resolvedDiagrams.isEmpty {
            rehighlight()
        }
        completeLayout()
    }

    /// A formula's picture in the current look, once `mathRenderer` has drawn it; the first call
    /// starts the drawing and re-renders the text when it lands (one pass however many land
    /// together). Every outcome is cached, misses too.
    func picture(forMath tex: String, display: Bool) -> MathPicture? {
        let request = MathRequest(tex: tex, display: display, theme: theme, dark: style.isDark, fontSize: style.body.pointSize)
        if let cached = mathCache[request] { return cached }
        guard !pendingMath.contains(request) else { return nil }
        pendingMath.insert(request)
        mathRenderer(request) { [weak self] picture in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingMath.remove(request)
                self.mathCache[request] = .some(picture)
                if picture != nil { self.scheduleRehighlight() }
            }
        }
        return nil
    }

    private func scheduleRehighlight() {
        guard !rehighlightScheduled else { return }
        rehighlightScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.rehighlightScheduled = false
            if self.presentation == .inline { self.rehighlight() }
        }
    }

    /// The column follows the width, and pictures are fitted to the text width, so a width change
    /// re-fits both; the text is laid out whole again once the width has settled.
    ///
    /// Until then the text's height is a guess, and the view does not get shorter on a guess: one
    /// below the visible part's height hides a scroll bar that takes room (System Settings ▸ Appearance
    /// ▸ Show scroll bars: Always, or a mouse), which widens the text, which drops the layout again,
    /// and the bar and the layout went round after each other.
    override func setFrameSize(_ newSize: NSSize) {
        let isNewWidth = newSize.width != layoutWidth
        if isNewWidth { awaitsLayout = true }
        super.setFrameSize(awaitsLayout ? NSSize(width: newSize.width, height: max(newSize.height, frame.height)) : newSize)
        guard isNewWidth else { return }
        layoutWidth = newSize.width
        isSettingWidth = true
        updateInsets()
        refitPictures()
        isSettingWidth = false
        scheduleLayoutCompletion()
    }

    /// Fits Live Preview's pictures (images, diagrams, formulas) to the text width again.
    private func refitPictures() {
        if presentation == .inline, !resolvedImages.isEmpty || !resolvedDiagrams.isEmpty || !resolvedMath.isEmpty {
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
            LinkOpener.open(url, from: baseURL, attachments: attachmentSearch, in: window)
        } else {
            setSelectedRange(NSRange(location: charIndex, length: 0))
        }
    }

    // MARK: Pasted and dropped attachments

    /// Pasteboard contents that become attachments: files first, then picture data.
    static let attachmentPasteboardTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]

    /// Files and pictures ahead of the inherited types, so a copied file or picture pastes (and
    /// drops) as an attachment while text still pastes as text.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        Self.attachmentPasteboardTypes + super.readablePasteboardTypes
    }

    override func dragOperation(for dragInfo: any NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        Self.attachmentPasteboardTypes.contains(type) && baseURL != nil ? .copy : super.dragOperation(for: dragInfo, type: type)
    }

    /// `paste:` lands here with the preferred type; files and pictures become attachments.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard Self.attachmentPasteboardTypes.contains(type), baseURL != nil else {
            return super.readSelection(from: pboard, type: type)
        }
        return importAttachments(from: pboard)
    }

    /// A drop of files or pictures inserts at the drop point; anything else is NSTextView's business.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard baseURL != nil, pasteboard.availableType(from: Self.attachmentPasteboardTypes) != nil else {
            return super.performDragOperation(sender)
        }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        return importAttachments(from: pasteboard)
    }

    /// Shows an attachment that could not be stored; nil means `presentError`. Tests replace it, since
    /// an error presented without a window is an app-modal alert.
    var presentImportError: ((Error) -> Void)?

    /// Copies the pasteboard's files (or writes its picture) where new attachments go and inserts
    /// the Markdown for them at the selection, undoably. False when it holds neither. An error is
    /// shown and counts as handled: NSTextView would otherwise paste the pasteboard's text, the file's
    /// path, in its place.
    @discardableResult
    func importAttachments(from pasteboard: NSPasteboard) -> Bool {
        guard let baseURL else { return false }
        let importer = AttachmentImporter(search: attachmentSearch, destination: attachmentDestination)
        do {
            let stored: [URL]
            if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL], !files.isEmpty {
                let urls = files.map { $0 as URL }
                if Self.isLargeImport(urls) {
                    importInBackground(urls, with: importer, for: baseURL)
                    return true
                }
                stored = try urls.map { try importer.store(fileAt: $0, for: baseURL) }
            } else if let picture = Self.pictureData(on: pasteboard) {
                stored = [try importer.store(picture.data, named: AttachmentImporter.pastedImageName(extension: picture.extension), for: baseURL)]
            } else {
                return false
            }
            let markdown = stored.map { AttachmentImporter.markdown(for: $0, relativeTo: baseURL) }.joined(separator: "\n")
            insertText(markdown, replacementRange: selectedRange())
            return true
        } catch {
            if let presentImportError { presentImportError(error) } else { _ = presentError(error) }
            return true
        }
    }

    /// Files at least this large in all, or any folder, are copied and compared off the main thread.
    static let largeImportBytes = 16 << 20

    /// Whether storing `urls` may take long: a folder (a tree to copy) or `largeImportBytes` and more.
    private static func isLargeImport(_ urls: [URL]) -> Bool {
        var total = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { return true }
            total += values?.fileSize ?? 0
        }
        return total >= largeImportBytes
    }

    /// Stores large files off the main thread (PERF-10: comparing and copying 256 MB froze the editor
    /// for 1.5–2.4 s) and inserts their Markdown when done: where the paste or drop was when the text
    /// is unchanged meanwhile, at the selection otherwise.
    private func importInBackground(_ urls: [URL], with importer: AttachmentImporter, for baseURL: URL) {
        let range = selectedRange()
        let before = string
        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try urls.map { try importer.store(fileAt: $0, for: baseURL) } }
            }.value
            guard let self else { return }
            switch result {
            case .success(let stored):
                let markdown = stored.map { AttachmentImporter.markdown(for: $0, relativeTo: baseURL) }.joined(separator: "\n")
                self.insertText(markdown, replacementRange: self.string == before ? range : self.selectedRange())
            case .failure(let error):
                if let presentImportError = self.presentImportError { presentImportError(error) } else { _ = self.presentError(error) }
            }
        }
    }

    /// PNG or JPEG bytes as they are on the pasteboard; any other picture re-encoded as PNG.
    private static func pictureData(on pasteboard: NSPasteboard) -> (data: Data, extension: String)? {
        if let data = pasteboard.data(forType: .png) { return (data, "png") }
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) { return (data, "jpg") }
        guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        return (png, "png")
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
    /// How many whole styling passes (`rehighlight()`) ran, for tests.
    private(set) var passes = 0

    /// Front matter, fenced code and `$$` blocks as of the last highlighting pass: Markdown takes them
    /// literally, so Return there is a line break, not a list or quote continuation that removed a
    /// marker-only YAML or console line or added `+ ` after a diff line (BUG-27).
    private var literalBlocks: [NSRange] = []

    private func isInLiteralBlock(_ location: Int) -> Bool {
        literalBlocks.contains { $0.location <= location && location <= NSMaxRange($0) }
    }
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
        } else if continuesLists, !isInLiteralBlock(selectedRange().location),
                  let edit = ListContinuation.edit(in: currentText, at: selectedRange().location) {
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
        if !isMovingVertically { verticalAnchor = nil }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !isApplyingPairEdit, let range = ranges.first?.rangeValue {
            pairing.selectionChanged(to: range)
        }
        updateReveal(stillSelecting: stillSelectingFlag)
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

    // MARK: Up and down

    /// Where ↑ and ↓ keep the caret, from the text container's left edge, while one follows another;
    /// any other change of the selection forgets it.
    private var verticalAnchor: CGFloat?
    private var isMovingVertically = false

    override func moveDown(_ sender: Any?) {
        if !moveCaret(down: true) { super.moveDown(sender) }
    }

    override func moveUp(_ sender: Any?) {
        if !moveCaret(down: false) { super.moveUp(sender) }
    }

    /// A line on screen: its glyphs, its rect in the text container, and whether it is the empty line
    /// after the text's last line break, which has no glyphs.
    private struct ScreenLine {
        let glyphs: NSRange
        let rect: NSRect
        var isExtra = false
    }

    /// ↑ and ↓ in the inline presentation: to the line on screen above or below, at the place the
    /// caret keeps. NSTextView's own pick the character from the next line's glyphs, and the hidden
    /// markers a paragraph starts with are laid out at the end of the line before it: ↓ landed on
    /// them, in the paragraph after the one it should reach, whenever that one was empty or shorter
    /// than the caret's place (the empty line before every heading, quote and code block was skipped).
    /// False when this does not apply (the source look, marked text, several selections).
    private func moveCaret(down: Bool) -> Bool {
        guard presentation == .inline, !hasMarkedText(), selectedRanges.count == 1, let layoutManager, let textContainer, let textStorage,
              textStorage.length > 0, textStorage.length <= Self.highlightingLimit else { return false }
        let text = textStorage.mutableString
        let selection = selectedRange()
        let caret = down ? NSMaxRange(selection) : selection.location
        let upstream = selection.length == 0 && selectionAffinity == .upstream
        guard let current = screenLine(ofCaretAt: caret, upstream: upstream) else { return false }
        let anchor = verticalAnchor ?? caretPlace(at: caret, in: current)
        var destination: (location: Int, affinity: NSSelectionAffinity)
        if let target = screenLine(next: down, to: current) {
            destination = character(at: anchor, in: target, text: text, layoutManager: layoutManager, textContainer: textContainer)
            if down, let block = collapsedBlock(endingInLineAt: destination.location, text: text) {
                // A block drawn as a picture shows its last line break only: ↓ enters it at its first line.
                destination = (block.location, .downstream)
            }
        } else {
            // Past the first or the last line: to the text's start or end, as NSTextView goes.
            destination = (down ? text.length : 0, .downstream)
        }
        isMovingVertically = true
        verticalAnchor = anchor
        setSelectedRanges([NSValue(range: NSRange(location: destination.location, length: 0))], affinity: destination.affinity, stillSelecting: false)
        isMovingVertically = false
        scrollRangeToVisible(selectedRange())
        return true
    }

    /// The diagram or formula block drawn as a picture whose last line holds `location`: the block's
    /// other lines are hidden, line breaks and all, so they are no lines on screen.
    private func collapsedBlock(endingInLineAt location: Int, text: NSString) -> NSRange? {
        guard let textStorage, location <= text.length else { return nil }
        let lineStart = text.lineRange(for: NSRange(location: location, length: 0)).location
        guard lineStart > 0, textStorage.attribute(.hiddenMarker, at: lineStart - 1, effectiveRange: nil) != nil else { return nil }
        return markers.blocks.first { $0.location < lineStart && NSLocationInRange(lineStart, $0) }
    }

    /// The line on screen the caret at `index` is in. A caret at a soft line break belongs to the line
    /// before it when `upstream`. An index whose glyphs are hidden (a selection ending where a rendered
    /// paragraph starts) counts as the first character of its line that shows.
    private func screenLine(ofCaretAt index: Int, upstream: Bool) -> ScreenLine? {
        guard let layoutManager, let textStorage, layoutManager.numberOfGlyphs > 0 else { return nil }
        let text = textStorage.mutableString
        if index >= text.length {
            if layoutManager.extraLineFragmentTextContainer != nil {
                return ScreenLine(glyphs: NSRange(location: layoutManager.numberOfGlyphs, length: 0), rect: layoutManager.extraLineFragmentRect, isExtra: true)
            }
            return screenLine(holdingGlyph: layoutManager.numberOfGlyphs - 1)
        }
        var visible = index
        var contentsEnd = 0
        text.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
        while visible < contentsEnd, textStorage.attribute(.hiddenMarker, at: visible, effectiveRange: nil) != nil { visible += 1 }
        let glyph = layoutManager.glyphIndexForCharacter(at: visible)
        guard let line = screenLine(holdingGlyph: glyph) else { return nil }
        if upstream, glyph == line.glyphs.location, glyph > 0, index > 0, !Self.isLineBreak(text.character(at: index - 1)) {
            return screenLine(holdingGlyph: glyph - 1)
        }
        return line
    }

    private func screenLine(holdingGlyph glyph: Int) -> ScreenLine? {
        guard let layoutManager, glyph >= 0, glyph < layoutManager.numberOfGlyphs else { return nil }
        var glyphs = NSRange()
        let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &glyphs)
        return glyphs.length > 0 ? ScreenLine(glyphs: glyphs, rect: rect) : nil
    }

    /// The line on screen after (or before) `line`; nil past the last (or the first).
    private func screenLine(next down: Bool, to line: ScreenLine) -> ScreenLine? {
        guard let layoutManager else { return nil }
        if down {
            guard !line.isExtra else { return nil }
            if NSMaxRange(line.glyphs) < layoutManager.numberOfGlyphs { return screenLine(holdingGlyph: NSMaxRange(line.glyphs)) }
            guard layoutManager.extraLineFragmentTextContainer != nil else { return nil }
            return ScreenLine(glyphs: NSRange(location: layoutManager.numberOfGlyphs, length: 0), rect: layoutManager.extraLineFragmentRect, isExtra: true)
        }
        return screenLine(holdingGlyph: (line.isExtra ? layoutManager.numberOfGlyphs : line.glyphs.location) - 1)
    }

    /// How far from the text container's left edge the caret at `index` stands in `line`.
    private func caretPlace(at index: Int, in line: ScreenLine) -> CGFloat {
        guard let layoutManager, let textContainer, let textStorage else { return 0 }
        if line.isExtra { return layoutManager.extraLineFragmentUsedRect.minX }
        let glyph = index < textStorage.length ? layoutManager.glyphIndexForCharacter(at: index) : layoutManager.numberOfGlyphs
        // After the line's last glyph: the text's end, or a soft line break the caret stays before.
        guard glyph < NSMaxRange(line.glyphs) else {
            return layoutManager.lineFragmentUsedRect(forGlyphAt: NSMaxRange(line.glyphs) - 1, effectiveRange: nil).maxX - textContainer.lineFragmentPadding
        }
        // Hidden glyphs before the line's first one that shows stand where it does.
        return line.rect.minX + layoutManager.location(forGlyphAt: max(glyph, line.glyphs.location)).x
    }

    /// The caret position in `line` nearest `place`: within the line of text `line` shows, so never on
    /// the hidden markers of the next paragraph that are laid out at its end. At the left edge of a
    /// paragraph's first line it is the paragraph's start, before the markers hidden there.
    private func character(at place: CGFloat, in line: ScreenLine, text: NSString, layoutManager: NSLayoutManager,
                           textContainer: NSTextContainer) -> (location: Int, affinity: NSSelectionAffinity) {
        guard !line.isExtra else { return (text.length, .downstream) }
        let first = layoutManager.characterIndexForGlyph(at: line.glyphs.location)
        var lineStart = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: first, length: 0))
        // Where the line on screen ends: at the line break, or before it where the text wraps.
        let shown = NSMaxRange(layoutManager.characterRange(forGlyphRange: line.glyphs, actualGlyphRange: nil))
        let wraps = shown < contentsEnd
        let end = wraps ? shown : contentsEnd
        var fraction: CGFloat = 0
        var index = layoutManager.characterIndex(for: NSPoint(x: place, y: line.rect.midY), in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
        if fraction > 0.5, index < text.length { index = NSMaxRange(text.rangeOfComposedCharacterSequence(at: index)) }
        if index <= first {
            // Left of the first character that shows: the paragraph's start when only hidden markers come before it.
            let startsParagraph = (lineStart..<first).allSatisfy { textStorage?.attribute(.hiddenMarker, at: $0, effectiveRange: nil) != nil }
            return (startsParagraph ? lineStart : first, .downstream)
        }
        guard index < end else { return (end, wraps ? .upstream : .downstream) }
        return (index, .downstream)
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        [0x0A, 0x0D, 0x2028, 0x2029, 0x0085].contains(character)
    }

    // MARK: Scrolling to the caret

    /// Room kept between the line scrolled into view and the edge of the visible part.
    static let scrollMargin: CGFloat = 8

    /// Scrolls the least that shows the lines of `range`, when they are less than half a screen away:
    /// the caret went a line up or down, or text was typed at the edge. NSTextView centers whatever
    /// was out of sight, so every arrow key at the edge of the visible part moved the text half a
    /// screen. What is further away (a search result, the other end of the document) is centered as
    /// before, with text around it.
    override func scrollRangeToVisible(_ range: NSRange) {
        guard let lines = rect(ofLinesIn: range) else {
            super.scrollRangeToVisible(range)
            return
        }
        let visible = visibleRect
        let wanted = lines.insetBy(dx: 0, dy: -Self.scrollMargin)
        let above = visible.minY - wanted.minY
        let below = wanted.maxY - visible.maxY
        guard above > 0 || below > 0 else { return }
        guard wanted.height <= visible.height, max(above, below) <= visible.height / 2 else {
            super.scrollRangeToVisible(range)
            return
        }
        scrollToVisible(NSRect(x: visible.minX, y: wanted.minY, width: visible.width, height: wanted.height))
    }

    /// The lines on screen that hold `range` (the caret's line for an empty one), in the view's coordinates.
    private func rect(ofLinesIn range: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0, NSMaxRange(range) <= textStorage.length else { return nil }
        let origin = textContainerOrigin
        if range.length == 0 {
            guard let line = screenLine(ofCaretAt: range.location, upstream: selectionAffinity == .upstream) else { return nil }
            return line.rect.offsetBy(dx: origin.x, dy: origin.y)
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).offsetBy(dx: origin.x, dy: origin.y)
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
        // The text's start is its top, with the room above the first line: the preview at its top
        // would otherwise leave the editor that room short.
        var y = line <= 0 ? 0 : rect.minY + fraction * rect.height + textContainerInset.height
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
    /// Hides markers (zero-width `.null` glyphs), draws list markers as bullets and makes a formula's
    /// anchor a control glyph, as the text's look says (`.hiddenMarker`, `.listBullet`, `.mathPicture`;
    /// see `markGlyphs`). Works only from the arrays it is handed and from the text's attributes: any
    /// glyph-tree query here throws "reentrant glyph generation problem" (probed 2026-09-15).
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard presentation == .inline, glyphRange.length > 0, let textStorage else { return 0 }
        let count = glyphRange.length
        let first = characterIndexes[0]
        let span = NSRange(location: first, length: characterIndexes[count - 1] - first + 1)
        guard NSMaxRange(span) <= textStorage.length else { return 0 }
        let hidden = Self.stretches(of: .hiddenMarker, in: span, of: textStorage)
        let bullets = Self.stretches(of: .listBullet, in: span, of: textStorage)
        let anchors = Self.stretches(of: .mathPicture, in: span, of: textStorage)
        guard !hidden.isEmpty || !bullets.isEmpty || !anchors.isEmpty else { return 0 }
        let bullet = bullets.isEmpty ? nil : bulletGlyph(for: font)
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
        var newProperties = Array(UnsafeBufferPointer(start: properties, count: count))
        func holds(_ stretches: [NSRange], _ character: Int) -> Bool {
            stretches.contains { NSLocationInRange(character, $0) }
        }
        for index in 0..<count {
            let character = characterIndexes[index]
            if holds(anchors, character) {
                newProperties[index] = .controlCharacter
            } else if holds(hidden, character) {
                newProperties[index] = .null
            } else if let bullet, holds(bullets, character) {
                newGlyphs[index] = bullet
            }
        }
        layoutManager.setGlyphs(newGlyphs, properties: newProperties, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return count
    }

    /// The stretches of `range` that carry `key`, in order.
    private static func stretches(of key: NSAttributedString.Key, in range: NSRange, of storage: NSTextStorage) -> [NSRange] {
        var found: [NSRange] = []
        var index = range.location
        while index < NSMaxRange(range) {
            var run = NSRange()
            if storage.attribute(key, at: index, longestEffectiveRange: &run, in: range) != nil {
                found.append(run)
            }
            index = max(NSMaxRange(run), index + 1)
        }
        return found
    }

    /// A formula's anchor is a control glyph laid out as whitespace of the picture's width…
    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        mathPicture(at: charIndex) != nil ? .whitespace : action
    }

    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer, proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(origin: glyphPosition, size: mathPicture(at: charIndex)?.size ?? NSSize(width: 0, height: proposedRect.height))
    }

    /// …and its line grows to hold the picture above and below the baseline, since the box's own
    /// height is ignored (probed 2026-09-16); the lines after follow. The first and the last line on
    /// screen of the revealed lines (`.revealStart`, `.revealEnd`) get the room for the band behind them
    /// (`InlineStyle.revealRoom`) outside their used rect, which the caret spans: paragraph spacing
    /// would not do, since TextKit 1 applies none before the text's first paragraph and none after a
    /// line whose fragment also holds the next paragraph's hidden markers (probed 2026-09-26).
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>, lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard presentation == .inline, let textStorage else { return false }
        let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characters.length > 0, NSMaxRange(characters) <= textStorage.length else { return false }
        var above: CGFloat = 0
        var below: CGFloat = 0
        for anchor in Self.stretches(of: .mathPicture, in: characters, of: textStorage) {
            guard let picture = mathPicture(at: anchor.location) else { continue }
            above = max(above, picture.baseline + InlineStyle.mathGap)
            below = max(below, picture.size.height - picture.baseline + InlineStyle.mathGap)
        }
        let extraAbove = max(0, above - baselineOffset.pointee)
        let extraBelow = max(0, below - (lineFragmentRect.pointee.height - baselineOffset.pointee))
        let startsReveal = !Self.stretches(of: .revealStart, in: characters, of: textStorage).isEmpty
        let endsReveal = !Self.stretches(of: .revealEnd, in: characters, of: textStorage).isEmpty
        let room = startsReveal || endsReveal ? InlineStyle(style: style).revealRoom : 0
        let roomAbove = startsReveal ? room : 0
        let roomBelow = endsReveal ? room : 0
        guard extraAbove > 0 || extraBelow > 0 || roomAbove > 0 || roomBelow > 0 else { return false }
        lineFragmentRect.pointee.size.height += extraAbove + extraBelow + roomAbove + roomBelow
        lineFragmentUsedRect.pointee.size.height += extraAbove + extraBelow
        lineFragmentUsedRect.pointee.origin.y += roomAbove
        baselineOffset.pointee += extraAbove + roomAbove
        return true
    }

    private func mathPicture(at index: Int) -> MathPicture? {
        guard let textStorage, index < textStorage.length else { return nil }
        return textStorage.attribute(.mathPicture, at: index, effectiveRange: nil) as? MathPicture
    }
}
