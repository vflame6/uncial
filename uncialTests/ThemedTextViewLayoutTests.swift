import AppKit
import Testing
import UncialCore
@testable import Uncial

/// What a long note's layout does while the caret moves through it, text is typed and pictures land.
/// TextKit estimates the positions of text it has not laid out, and a styling pass that touched the
/// whole document left everything on such guesses: the arrow keys picked lines from them, the scroll
/// position jumped and the document's height was a fraction of the real one.
///
/// The tests walk long notes on the main actor, which other suites' timers share: they yield as they go.
@MainActor
@Suite struct ThemedTextViewLayoutTests {

    /// Sections of a heading, a paragraph that wraps, a list and fenced code, with a table and a callout
    /// now and then, and characters that need another font.
    private func note(sections: Int) -> String {
        var text = "# A long note\n\nAn introduction with an emoji 😀 and 漢字.\n\n"
        for section in 1...sections {
            text += "## Section \(section)\n\n"
            text += "Paragraph \(section) with **bold**, *italic*, `code` and a [link](https://example.com/\(section)). It goes on long "
                + "enough to wrap over two or three lines at the width of the column, so that the lines on screen and the lines of the "
                + "text differ, as they do in a real note.\n\n"
            text += "- item one of \(section)\n- [ ] a task\n  - a nested item with `code`\n\n"
            text += "```swift\nfunc example\(section)() {\n    let x = \(section)\n    print(x)\n    // a comment\n}\n```\n\n"
            if section % 4 == 0 {
                text += "| Name | Value |\n|------|-------|\n| a\(section) | 1 |\n| b | 22 |\n\n"
            }
            if section % 5 == 0 {
                text += "> [!note] Note \(section)\n> the body of the callout\n\n"
            }
        }
        return text
    }

    private func start(of needle: String, in text: String) -> Int {
        (text as NSString).range(of: needle).location
    }

    /// A few lines of every construct Live Preview renders.
    private static let sampler = [
        "# Title", "",
        "A paragraph with **bold**, *italic*, `code`, a [link](https://example.com) and a footnote[^1].", "",
        "## Heading two", "",
        "- an item", "- [ ] a task with **bold**", "  - nested", "",
        "1. first", "2. second", "",
        "> a quote line", "> another quote line", "",
        "> [!warning] Careful", "> the callout's body", "",
        "```swift", "let x = 1", "```", "",
        "| Name | Value |", "|------|------:|", "| a | 1 |", "| bb | 22 |", "",
        "Setext", "======", "",
        "Inline $x^2$ math, then a block:", "",
        "$$", "y = x", "$$", "",
        "```mermaid", "graph TD", "  A --> B", "```", "",
        "![shot](shot.png)", "",
        "<b>bold</b> and <i>italic</i> HTML", "",
        "---", "",
        "[^1]: The footnote.", "",
        "The end.", "",
    ].joined(separator: "\n")

    /// An editor on `text` with a picture for every image, diagram and formula, drawn before it returns.
    private func illustrated(_ text: String) async -> EditorWindow {
        let diagram = NSImage.filled(with: .blue, size: NSSize(width: 300, height: 120))
        let formula = MathPicture(image: NSImage.filled(with: .green, size: NSSize(width: 60, height: 20)), size: NSSize(width: 60, height: 20), baseline: 15)
        let picture = NSImage.filled(with: .red, size: NSSize(width: 200, height: 100))
        let editor = EditorWindow(text) { view in
            view.isContinuousSpellCheckingEnabled = false
            view.loadsRemoteImages = true
            view.baseURL = URL(string: "https://example.com/notes/")
            view.remoteImageLoader = { _, completion in completion(picture) }
            view.diagramRenderer = { _, completion in completion(diagram) }
            view.mathRenderer = { _, completion in completion(formula) }
        }
        let view = editor.textView
        await eventually { !view.resolvedDiagrams.isEmpty && !view.resolvedMath.isEmpty && !view.resolvedImages.isEmpty }
        return editor
    }

    /// The layout as it stands is the layout the whole text gets when every glyph and line is made
    /// again: the same lines on screen, at the same places, with the same characters hidden.
    private func expectWholeLayout(_ editor: EditorWindow, _ when: @autoclosure () -> String, sourceLocation: SourceLocation = #_sourceLocation) {
        let now = editor.layoutSnapshot()
        let whole = editor.layoutSnapshotMadeAgain()
        guard now != whole else { return }
        let lines = (0..<max(now.count, whole.count)).filter { index in
            (index < now.count ? now[index] : "") != (index < whole.count ? whole[index] : "")
        }
        let first = lines.prefix(2).map { "is \($0 < now.count ? now[$0] : "none"), should be \($0 < whole.count ? whole[$0] : "none")" }
        Issue.record("\(when()): \(lines.count) lines on screen differ from a layout of the whole text. \(first.joined(separator: "; "))", sourceLocation: sourceLocation)
    }

    /// The lines of `text`: where each starts and where its characters end.
    private func lines(of text: String) -> [(start: Int, end: Int)] {
        let source = text as NSString
        var lines: [(Int, Int)] = []
        var location = 0
        while location < source.length {
            var start = 0, next = 0, end = 0
            source.getLineStart(&start, end: &next, contentsEnd: &end, for: NSRange(location: location, length: 0))
            lines.append((start, end))
            location = next
        }
        return lines
    }

    /// ↓ stops on every line, the empty ones and the short ones too, keeps its place across them, and
    /// ends at the text's end; ↑ goes back the same way. The markers hidden at the start of a heading,
    /// a quote or a code block are laid out at the end of the line before, and NSTextView's own ↓ landed
    /// on them: the line before was skipped whenever it was empty or shorter than the caret's place.
    @Test func arrowKeysStopOnEveryLine() {
        // Lines: a paragraph, empty, a heading, empty, "short", a quote, empty, a fence, code, a fence, empty, a last line.
        let text = "First paragraph that is long enough to have some width in it.\n\n## Heading two\n\nshort\n> quoted line\n\n```swift\nlet x = 1\n```\n\nlast line here\n"
        let editor = EditorWindow(text)
        defer { editor.close() }
        let view = editor.textView
        view.setSelectedRange(NSRange(location: 20, length: 0))
        var lines: [Int] = []
        for _ in 1...13 {
            view.moveDown(nil)
            lines.append(view.lineIndex.line(at: view.selectedRange().location))
            if lines.count == 4 {
                // "short" ends left of the caret's place: the caret is at its end, not in the quote below.
                #expect(view.selectedRange().location == start(of: "short", in: text) + 5)
            }
            if lines.count == 11 {
                // Past the empty lines the caret is back at its place, not at the line's start.
                #expect(view.selectedRange().location > start(of: "last line here", in: text) + 5)
            }
        }
        #expect(lines == Array(1...12) + [12])
        #expect(view.selectedRange().location == (text as NSString).length)
        lines = []
        for _ in 1...13 {
            view.moveUp(nil)
            lines.append(view.lineIndex.line(at: view.selectedRange().location))
        }
        #expect(lines == Array((0...11).reversed()) + [0])
        #expect(view.selectedRange().location == 0)
    }

    /// ↓ enters a diagram or a formula block that is drawn as a picture at its first line, as ↑ enters
    /// it at its last, so every line of its source is a stop either way: only the block's last line
    /// break shows while the picture is drawn, and ↓ went to the closing fence and out again.
    @Test func arrowKeysWalkThroughABlockDrawnAsAPicture() async {
        // Lines: intro, a diagram of four lines, between, a formula block of three lines, after.
        let text = "intro\n```mermaid\ngraph TD\n  A --> B\n```\nbetween\n$$\ny = x\n$$\nafter\n"
        let editor = await illustrated(text)
        defer { editor.close() }
        let view = editor.textView
        #expect(view.resolvedDiagrams.count == 1 && view.resolvedMath.count == 1)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        var lines: [Int] = []
        for _ in 1...9 {
            view.moveDown(nil)
            lines.append(view.lineIndex.line(at: view.selectedRange().location))
        }
        #expect(lines == Array(1...9))
        lines = []
        for _ in 1...9 {
            view.moveUp(nil)
            lines.append(view.lineIndex.line(at: view.selectedRange().location))
        }
        #expect(lines == Array((0...8).reversed()))
    }

    /// The text stays laid out, at its real height, and the view scrolls no further than the caret needs
    /// while the caret walks through the note, a line at the edge of the visible part: every move to
    /// another paragraph used to shrink the document to an estimate and scroll thousands of points, and
    /// NSTextView centers a caret that leaves the visible part, half a screen at every such key.
    @Test func caretMovesKeepTheLayoutAndThePlace() async {
        let text = note(sections: 40)
        let editor = EditorWindow(text)
        defer { editor.close() }
        let view = editor.textView
        let layoutManager = view.layoutManager!
        editor.moveCaret(to: start(of: "Paragraph 20 with", in: text))
        let height = view.frame.height
        var scrolled = 0
        for step in 1...40 {
            let offset = editor.scrollOffset
            view.moveDown(nil)
            #expect(!layoutManager.hasNonContiguousLayout, "↓ \(step) left text that is not laid out")
            #expect(abs(view.frame.height - height) < 200, "↓ \(step) made the text \(view.frame.height) points high, from \(height)")
            #expect(abs(editor.scrollOffset - offset) < 80, "↓ \(step) scrolled from \(offset) to \(editor.scrollOffset)")
            if editor.scrollOffset != offset { scrolled += 1 }
            let caret = editor.visibleTop(ofCharacterAt: view.selectedRange().location)
            #expect(caret >= 0 && caret < editor.scrollView.contentView.bounds.height, "↓ \(step) left the caret at \(caret)")
            await Task.yield()
        }
        // The caret reached the edge and went on line by line.
        #expect(scrolled > 10)
        // Laid out move by move, the text is as high as laid out at once.
        let moved = layoutManager.usedRect(for: view.textContainer!).height
        #expect(abs(editor.heightLaidOutAgain() - moved) < 0.5)
    }

    /// A caret move changes the look of the paragraph it leaves and the one it enters, nothing else.
    @Test func aCaretMoveRestylesItsParagraphsOnly() {
        let text = note(sections: 40)
        let editor = EditorWindow(text)
        defer { editor.close() }
        let view = editor.textView
        let paragraph = (text as NSString).paragraphRange(for: NSRange(location: start(of: "Paragraph 20 with", in: text), length: 0))
        editor.moveCaret(to: paragraph.location)
        let list = start(of: "- item one of 20", in: text)
        let edits = StorageEdits.during(view.textStorage!) { editor.moveCaret(to: list) }
        #expect(!edits.isEmpty)
        for edit in edits {
            #expect(edit.location >= paragraph.location && NSMaxRange(edit) <= list + 40, "restyled \(edit)")
        }
        #expect(view.revealed == (text as NSString).lineRange(for: NSRange(location: list, length: 0)))
    }

    /// A note opens laid out whole, at its real height (it was an estimate, a quarter of it, that grew as
    /// the view scrolled into it), and typing restyles what the edit changed: a keystroke in the middle of
    /// a long note used to have the whole of it styled and laid out again, in every mode, and the view
    /// scrolled away.
    @Test(arguments: [EditorPresentation.inline, .source])
    func typingRestylesWhatChanged(_ presentation: EditorPresentation) {
        let text = note(sections: 40)
        let editor = EditorWindow(text, presentation: presentation)
        defer { editor.close() }
        let view = editor.textView
        #expect(view.layoutManager?.hasNonContiguousLayout == false && view.frame.height > 10_000)
        #expect(abs(editor.heightLaidOutAgain() + 2 * view.textContainerInset.height - view.frame.height) < 1)
        let paragraph = (text as NSString).paragraphRange(for: NSRange(location: start(of: "Paragraph 20 with", in: text), length: 0))
        editor.moveCaret(to: paragraph.location + 12)
        let offset = editor.scrollOffset
        let edits = StorageEdits.during(view.textStorage!) {
            view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        #expect(view.string.utf16.count == text.utf16.count + 1)
        for edit in edits {
            #expect(edit.location >= paragraph.location - 1 && NSMaxRange(edit) <= NSMaxRange(paragraph) + 2, "restyled \(edit)")
        }
        #expect(view.layoutManager?.hasNonContiguousLayout == false)
        #expect(abs(editor.scrollOffset - offset) < 30)
        let typed = view.layoutManager!.usedRect(for: view.textContainer!).height
        #expect(abs(editor.heightLaidOutAgain() - typed) < 0.5)
    }

    /// A pass over a text that already has its look changes nothing, so nothing is laid out again: the
    /// passes after a picture lands or the window is resized cost the document no layout.
    @Test(arguments: Theme.allCases)
    func aPassWithNothingNewTouchesNothing(_ theme: Theme) {
        let editor = EditorWindow(note(sections: 6)) { $0.theme = theme }
        defer { editor.close() }
        let view = editor.textView
        editor.moveCaret(to: start(of: "Paragraph 3 with", in: view.string))
        let edits = StorageEdits.during(view.textStorage!) { view.rehighlight() }
        #expect(edits.isEmpty, "restyled \(edits)")
    }

    /// From a new width until the text is laid out whole at it, the view does not get shorter: its
    /// height is a guess then (a third of the real one here), and a guess below the visible part hides
    /// a scroll bar that takes room (Show scroll bars: Always, or a mouse), which widens the text, which
    /// drops the layout again: the bar and the layout chased each other for as long as the window was open.
    @Test func theTextKeepsItsHeightWhileANewWidthSettles() async {
        let editor = EditorWindow(note(sections: 12), width: 600, height: 420)
        defer { editor.close() }
        let view = editor.textView
        let height = view.frame.height
        var lowest = height
        let observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: nil) { _ in
            MainActor.assumeIsolated { lowest = min(lowest, view.frame.height) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        // As much narrower as a scroll bar makes it.
        editor.window.setContentSize(NSSize(width: 583, height: 420))
        editor.window.layoutIfNeeded()
        if let rep = editor.scrollView.bitmapImageRepForCachingDisplay(in: editor.scrollView.bounds) {
            editor.scrollView.cacheDisplay(in: editor.scrollView.bounds, to: rep)
        }
        #expect(view.frame.width == 583 && view.layoutManager?.hasNonContiguousLayout == true)
        #expect(lowest >= height, "the text went down to \(lowest) points from \(height)")
        await eventually { view.layoutManager?.hasNonContiguousLayout == false }
        #expect(view.layoutManager?.hasNonContiguousLayout == false && lowest >= height)
        #expect(abs(editor.heightLaidOutAgain() + 2 * view.textContainerInset.height - view.frame.height) < 1)
    }

    /// A picture that lands above the visible text takes its room without moving what is on screen.
    @Test func aPictureLandingAboveLeavesTheVisibleTextInPlace() async throws {
        let picture = NSImage.filled(with: .red, size: NSSize(width: 400, height: 300))
        var landings: [(NSImage?) -> Void] = []
        let text = "Intro\n\n![shot](https://example.com/shot.png)\n\n" + note(sections: 30)
        let editor = EditorWindow(text) { view in
            view.loadsRemoteImages = true
            view.remoteImageLoader = { _, completion in landings.append(completion) }
        }
        defer { editor.close() }
        let view = editor.textView
        let caret = start(of: "Paragraph 15 with", in: text)
        editor.moveCaret(to: caret)
        let top = editor.visibleTop(ofCharacterAt: caret)
        let height = view.frame.height
        #expect(landings.count == 1)
        landings.forEach { $0(picture) }
        await eventually { !view.resolvedImages.isEmpty }
        #expect(view.resolvedImages.count == 1)
        #expect(abs(view.frame.height - height - 300 - InlineStyle.imageGap) < 1)
        #expect(abs(editor.visibleTop(ofCharacterAt: caret) - top) < 1)
    }

    /// The look and the layout a caret move leaves are the ones a whole pass gives, on every kind of line:
    /// a pass after the move finds nothing to change, and making every glyph and line again changes
    /// nothing on screen.
    @Test func movingTheCaretStylesLikeAWholePass() async {
        let editor = await illustrated(Self.sampler)
        defer { editor.close() }
        let view = editor.textView
        let starts = lines(of: Self.sampler).map(\.start)
        // Down the text, then between lines far apart.
        for location in starts + [starts[40], starts[2], starts[24], starts[13]] {
            view.setSelectedRange(NSRange(location: location, length: 0))
            let pictures = (view.resolvedImages, view.resolvedDiagrams, view.resolvedMath)
            let markers = view.markers
            let edits = StorageEdits.during(view.textStorage!) { view.rehighlight() }
            #expect(edits.isEmpty, "a pass after moving to \(location) restyled \(edits)")
            #expect(view.markers == markers, "a pass after moving to \(location) found other markers")
            #expect(pictures == (view.resolvedImages, view.resolvedDiagrams, view.resolvedMath), "a pass after moving to \(location) found other pictures")
            expectWholeLayout(editor, "after moving to \(location)")
        }
    }

    /// The same under a `$$` that is not closed: there the reveal's blocks run from a fence to the next
    /// one, whatever it opens or closes, while code is colored by fences alone, and a caret move onto a
    /// code line restyled it without its fence, in the plain code color.
    @Test func movingTheCaretUnderAnUnclosedFormulaStylesLikeAWholePass() {
        let text = "$$\n\n```swift\nlet x = 1\n```\n\ntext\n\n```js\nvar y = 2\n```\n"
        let editor = EditorWindow(text) { $0.isContinuousSpellCheckingEnabled = false }
        defer { editor.close() }
        let view = editor.textView
        let starts = lines(of: text).map(\.start)
        for location in starts + starts.reversed() + [(text as NSString).length] {
            view.setSelectedRange(NSRange(location: location, length: 0))
            let markers = view.markers
            let edits = StorageEdits.during(view.textStorage!) { view.rehighlight() }
            #expect(edits.isEmpty, "a pass after moving to \(location) restyled \(edits)")
            #expect(view.markers == markers, "a pass after moving to \(location) found other markers")
            expectWholeLayout(editor, "after moving to \(location)")
        }
    }

    /// Typing and deleting leave the layout the whole text would get, at the end and the start of every
    /// kind of line. TextKit makes the glyphs and the lines again as soon as a character changes, before
    /// the text is styled: the glyphs took their hiding from the positions of the text before the edit,
    /// and typing at the end of a paragraph hid the wrong characters of the heading, list item or quote
    /// after it; Replace All left dozens of characters wrongly hidden.
    @Test func editsLeaveTheLayoutOfTheWholeText() async {
        let editor = await illustrated(Self.sampler)
        defer { editor.close() }
        let view = editor.textView
        for line in lines(of: Self.sampler).indices {
            for atEnd in [true, false] {
                let current = lines(of: view.string)[line]
                view.setSelectedRange(NSRange(location: atEnd ? current.end : current.start, length: 0))
                let place = "\(atEnd ? "the end" : "the start") of line \(line)"
                view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
                expectWholeLayout(editor, "after typing at \(place)")
                view.deleteBackward(nil)
                expectWholeLayout(editor, "after deleting at \(place)")
            }
            await Task.yield()
        }
        #expect(view.string == Self.sampler)
        // A line break at the end of every line, and the line joined again.
        for line in lines(of: Self.sampler).indices.reversed() {
            let length = view.string.utf16.count
            view.setSelectedRange(NSRange(location: lines(of: view.string)[line].end, length: 0))
            view.insertNewline(nil)
            expectWholeLayout(editor, "after Return at the end of line \(line)")
            for _ in 0..<8 where view.string.utf16.count > length {
                view.deleteBackward(nil)
            }
            expectWholeLayout(editor, "after joining line \(line) again")
            await Task.yield()
        }
        // Replace All: several paragraphs the caret is not in, at once.
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let text = view.string as NSString
        var matches: [NSRange] = []
        var search = NSRange(location: 0, length: text.length)
        while case let found = text.range(of: "line", options: [], range: search), found.location != NSNotFound {
            matches.append(found)
            search = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
        }
        #expect(matches.count > 2)
        if view.shouldChangeText(inRanges: matches.map { NSValue(range: $0) }, replacementStrings: matches.map { _ in "row" }) {
            view.textStorage?.beginEditing()
            matches.reversed().forEach { view.textStorage?.replaceCharacters(in: $0, with: "row") }
            view.textStorage?.endEditing()
            view.didChangeText()
        }
        expectWholeLayout(editor, "after replacing every \"line\"")
    }

    /// What is far from the visible part (a search result, the document's end) still comes to its
    /// middle, with text around it.
    @Test func aFarRangeComesToTheMiddle() {
        let text = note(sections: 40)
        let editor = EditorWindow(text)
        defer { editor.close() }
        let far = start(of: "Paragraph 30 with", in: text)
        editor.textView.scrollRangeToVisible(NSRange(location: far, length: 9))
        let top = editor.visibleTop(ofCharacterAt: far)
        let height = editor.scrollView.contentView.bounds.height
        #expect(top > height / 4 && top < height * 3 / 4, "the range is \(top) points down a visible part of \(height)")
    }

    /// Scrolled to its first line (the preview is at its top, in Split View), the editor is at its top,
    /// the room above the first line showing: it used to stop that room short, the first line against
    /// the window's edge, as soon as the preview had loaded.
    @Test func scrollingToTheFirstLineShowsTheTop() {
        let editor = EditorWindow(note(sections: 10), presentation: .source)
        defer { editor.close() }
        let view = editor.textView
        #expect(editor.scrollOffset == 0)
        view.scroll(toLine: 12)
        #expect(editor.scrollOffset > 100 && abs(view.visibleTopLine() - 12) < 0.01)
        view.scroll(toLine: 0)
        #expect(editor.scrollOffset == 0 && view.visibleTopLine() == 0)
    }
}
