import AppKit
import Testing
import UncialCore
@testable import Uncial

/// Stands in for `MarkdownTextView.Coordinator`: the model takes the text, then the view rehighlights.
@MainActor
private final class CoordinatorMirror: NSObject, NSTextViewDelegate {
    var changes = 0
    var model = ""

    func textDidChange(_ notification: Notification) {
        guard let view = notification.object as? ThemedTextView else { return }
        changes += 1
        model = view.string
        view.rehighlight()
    }
}

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

    /// Shortening the text inside a block that ends the document (an unclosed fence, a fence with no
    /// newline after it, a callout, a `$$` block) used to check the reveal against the old block
    /// ranges while the storage was still processing the edit: the edit raised and never reached
    /// the delegate, and the next one crashed the app.
    @Test func editsAtTheEndOfATrailingBlockReachTheDelegate() {
        let cases: [(text: String, caret: Int)] = [
            ("intro\n```swift\nlet x", 20),
            ("intro\n```swift\nlet x\n```", 20),
            ("intro\n\n> [!note] Hi\n> body", 26),
            ("intro\n$$\nx^2", 12),
        ]
        for (text, caret) in cases {
            let view = editor(text, presentation: .inline, caret: caret)
            let mirror = CoordinatorMirror()
            view.delegate = mirror
            view.deleteBackward(nil)
            view.deleteBackward(nil)
            let expected = (text as NSString).replacingCharacters(in: NSRange(location: caret - 2, length: 2), with: "")
            #expect(view.string == expected)
            #expect(mirror.changes == 2)
            #expect(mirror.model == expected)
            #expect(view.textStorage?.editedMask.isEmpty == true)
        }
    }

    /// Reload or a change on disk replaces the text with a shorter one while a block ended the old text.
    @Test func replacingWithShorterTextRevealsWithinIt() {
        let view = editor("intro\n```swift\nlet x = 1\n```", presentation: .inline, caret: 0)
        view.replaceText(with: "intro\n```swift\nlet")
        #expect(view.string == "intro\n```swift\nlet")
        #expect(view.revealed == NSRange(location: 0, length: 6))
        let atEnd = editor("intro\n```swift\nlet x = 1\n```", presentation: .inline, caret: 27)
        atEnd.replaceText(with: "intro\n```swift\nlet")
        #expect(atEnd.revealed == NSRange(location: 6, length: 12))
    }

    /// The caret's line is raw (SF Mono, as in the source presentation) and every other line rendered.
    @Test func hidesMarkersExceptOnTheCaretLine() {
        let source = editor(sample, presentation: .source, caret: 32)
        let inline = editor(sample, presentation: .inline, caret: 32)
        #expect(inline.revealed == NSRange(location: 30, length: 7))
        #expect(abs(width(inline, line: 2) - width(source, line: 2)) < 0.5)
        #expect(inline.markers.isHidden(0) && inline.markers.isHidden(16) && !inline.markers.isHidden(30))
        let renderedHeading = width(inline, line: 0)
        let renderedBold = width(inline, line: 1)
        #expect(abs(renderedBold - width(source, line: 1)) > 0.5)
        #expect(!(inline.textStorage!.attribute(.font, at: 11, effectiveRange: nil) as! NSFont).isFixedPitch)
        #expect((inline.textStorage!.attribute(.font, at: 30, effectiveRange: nil) as! NSFont).isFixedPitch)

        inline.setSelectedRange(NSRange(location: 20, length: 0))
        layout(inline)
        #expect(inline.revealed == NSRange(location: 11, length: 19))
        #expect(abs(width(inline, line: 1) - width(source, line: 1)) < 0.5)
        #expect(abs(width(inline, line: 0) - renderedHeading) < 0.5)
        #expect((inline.textStorage!.attribute(.font, at: 11, effectiveRange: nil) as! NSFont).isFixedPitch)

        inline.setSelectedRange(NSRange(location: 2, length: 0))
        layout(inline)
        #expect(abs(width(inline, line: 0) - width(source, line: 0)) < 0.5)
        #expect(abs(width(inline, line: 1) - renderedBold) < 0.5)

        inline.setSelectedRange(NSRange(location: 43, length: 0))
        layout(inline)
        #expect(inline.revealed == NSRange(location: 37, length: 17))
        #expect(abs(width(inline, line: 3) - width(source, line: 3)) < 0.5)
        #expect(abs(width(inline, line: 0) - renderedHeading) < 0.5)
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
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 300).fill()
        context.cgContext.translateBy(x: 0, y: 300)
        context.cgContext.scaleBy(x: 1, y: -1)
        layoutManager.drawBackground(forGlyphRange: layoutManager.glyphRange(for: inline.textContainer!), at: inline.textContainerOrigin)
        NSGraphicsContext.restoreGraphicsState()
        let left = inline.textContainerOrigin.x
        // Lines differ in height now (code is smaller), so each is found from its line break.
        func pixel(_ x: CGFloat, _ line: Int, _ fraction: CGFloat = 0.5) -> NSColor? {
            let newline = NSMaxRange(inline.lineIndex.range(ofLine: line))
            let glyph = layoutManager.glyphIndexForCharacter(at: min(newline, (text as NSString).length - 1))
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            return rep.colorAt(x: Int(left + x), y: Int(inline.textContainerOrigin.y + rect.minY + rect.height * fraction))
        }
        func isRed(_ color: NSColor?) -> Bool { color.map { $0.redComponent > 0.9 && $0.greenComponent < 0.1 } ?? false }
        func isBlue(_ color: NSColor?) -> Bool { color.map { $0.blueComponent > 0.9 && $0.redComponent < 0.1 } ?? false }
        #expect(!isBlue(pixel(100, 0)) && isBlue(pixel(100, 1)) && !isBlue(pixel(100, 2)))
        #expect(!isRed(pixel(100, 3)) && isRed(pixel(100, 4)) && isRed(pixel(100, 5)) && isRed(pixel(100, 6)) && !isRed(pixel(100, 7)))
        #expect(isBlue(pixel(3, 7)) && !isBlue(pixel(19, 7)))
        #expect(isBlue(pixel(3, 8)) && isBlue(pixel(19, 8)))
        #expect(!isBlue(pixel(3, 9)) && !isRed(pixel(100, 9)))
    }

    /// A revealed rule line (setext underline, `---`, table delimiter) shows its raw text, not the rule.
    @Test func revealedRulesAreNotDrawn() {
        let text = "Title\n===\n\n---\nend"
        let inline = editor(text, presentation: .inline, caret: 0)
        let layoutManager = inline.layoutManager as! InlineLayoutManager
        layoutManager.lineColor = .blue
        func ruleDrawn(on line: Int) -> Bool {
            layout(inline)
            let newline = NSMaxRange(inline.lineIndex.range(ofLine: line))
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: newline), effectiveRange: nil)
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
            let color = rep.colorAt(x: Int(inline.textContainerOrigin.x + 100), y: Int(inline.textContainerOrigin.y + floor(fragment.midY)))
            return color.map { $0.blueComponent > 0.9 && $0.redComponent < 0.1 } ?? false
        }
        #expect(ruleDrawn(on: 1) && ruleDrawn(on: 3))
        inline.setSelectedRange(NSRange(location: 6, length: 0))
        #expect(!ruleDrawn(on: 1) && ruleDrawn(on: 3))
        inline.setSelectedRange(NSRange(location: 11, length: 0))
        #expect(ruleDrawn(on: 1) && !ruleDrawn(on: 3))
        #expect(inline.revealed == NSRange(location: 11, length: 4))
    }

    /// Remote images load asynchronously through the injected loader and then hide their markers.
    @Test func revealsAWholeCalloutAroundTheCaret() {
        // Lines: `> [!note] Hi` 0–11, `> body` 13–18, `after` 20–24.
        let text = "> [!note] Hi\n> body\nafter"
        let inside = editor(text, presentation: .inline, caret: 15)
        #expect(inside.revealed == NSRange(location: 0, length: 20))
        #expect(inside.textStorage?.attribute(.font, at: 10, effectiveRange: nil) as? NSFont == inside.style.regular)
        #expect(inside.layoutManager?.propertyForGlyph(at: inside.layoutManager!.glyphIndexForCharacter(at: 0)) != .null)
        let outside = editor(text, presentation: .inline, caret: 22)
        #expect(outside.revealed == NSRange(location: 20, length: 5))
        #expect(outside.textStorage?.attribute(.font, at: 10, effectiveRange: nil) as? NSFont == outside.style.calloutTitleFont)
        #expect(outside.layoutManager?.propertyForGlyph(at: outside.layoutManager!.glyphIndexForCharacter(at: 2)) == .null)
        #expect(outside.textStorage?.attribute(.blockDecoration, at: 13, effectiveRange: nil) as? String == "callout:note")
    }

    @Test func loadsRemoteImagesAsynchronously() async throws {
        let picture = NSImage(size: NSSize(width: 20, height: 10), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        var requested: [URL] = []
        // The loader must be in place before the first render, which is what starts the fetch.
        let inline = ThemedTextView.standalone()
        inline.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        inline.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        inline.presentation = .inline
        inline.loadsRemoteImages = true
        inline.remoteImageLoader = { url, completion in
            requested.append(url)
            DispatchQueue.main.async { completion(url.lastPathComponent == "a.png" ? picture : nil) }
        }
        inline.replaceText(with: "![r](https://example.com/a.png)\nend")
        inline.setSelectedRange(NSRange(location: 33, length: 0))
        #expect(inline.resolvedImages.isEmpty && requested.map(\.absoluteString) == ["https://example.com/a.png"])
        try await Task.sleep(for: .milliseconds(200))
        #expect(inline.resolvedImages == [0])
        #expect(inline.markers.isHidden(0) && inline.markers.isHidden(4))
        inline.rehighlight()
        #expect(requested.count == 1)
    }

    /// Off by default: no fetch, the image stays source; turning it on fetches.
    @Test func leavesRemoteImagesAloneUnlessAllowed() {
        var requested = 0
        let inline = ThemedTextView.standalone()
        inline.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        inline.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        inline.presentation = .inline
        inline.remoteImageLoader = { _, _ in requested += 1 }
        inline.replaceText(with: "![r](https://example.com/a.png)\nend")
        inline.setSelectedRange(NSRange(location: 33, length: 0))
        #expect(inline.loadsRemoteImages == false)
        #expect(requested == 0 && inline.resolvedImages.isEmpty)
        #expect(!inline.markers.isHidden(0))
        inline.loadsRemoteImages = true
        #expect(requested == 1)
    }

    /// Resizing Live Preview asks for a new diagram picture only when the text width reaches another
    /// step, and the picture it has stays on screen meanwhile: every point of width used to queue a
    /// WebKit bitmap on the shared stage and show the diagram's source until it landed.
    @Test func resizingKeepsDiagramPicturesAndAsksForFew() async throws {
        let picture = NSImage(size: NSSize(width: 100, height: 40), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        var requests: [DiagramRequest] = []
        var pending: [(NSImage?) -> Void] = []
        let inline = ThemedTextView.standalone()
        inline.frame = NSRect(x: 0, y: 0, width: 700, height: 300)
        inline.textContainer?.containerSize = NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude)
        inline.presentation = .inline
        inline.diagramRenderer = { request, completion in
            requests.append(request)
            pending.append(completion)
        }
        inline.replaceText(with: "intro\n```mermaid\ngraph TD\n  A --> B\n```\nafter")
        inline.setSelectedRange(NSRange(location: 0, length: 0))
        func land() async throws {
            let waiting = pending
            pending = []
            waiting.forEach { $0(picture) }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await land()
        #expect(inline.resolvedDiagrams == [6])
        for width in stride(from: 699.0, through: 600.0, by: -1.0) {
            inline.setFrameSize(NSSize(width: width, height: 300))
            #expect(inline.resolvedDiagrams == [6], "no picture at width \(width)")
            try await land()
        }
        #expect(requests.count <= 6, "\(requests.count) pictures for a 100-point resize")
    }

    @Test func drawsDiagramsUnlessTheCaretIsInside() async throws {
        let picture = NSImage(size: NSSize(width: 100, height: 40), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        var requests: [DiagramRequest] = []
        let inline = ThemedTextView.standalone()
        inline.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        inline.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        inline.presentation = .inline
        inline.theme = .github
        inline.diagramRenderer = { request, completion in
            requests.append(request)
            DispatchQueue.main.async { completion(picture) }
        }
        // "intro\n" 0–5, "```mermaid" 6–15, "pie" 17–19, "  \"a\" : 1" 21–29, "```" 31–33, "\n" 34, "after" 35–39.
        inline.replaceText(with: "intro\n```mermaid\npie\n  \"a\" : 1\n```\nafter")
        inline.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(inline.resolvedDiagrams.isEmpty)
        #expect(requests.map(\.source) == ["pie\n  \"a\" : 1"] && requests.first?.theme == .github && requests.first?.dark == false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(inline.resolvedDiagrams == [6])
        #expect(inline.markers.isHidden(6) && inline.markers.isHidden(33) && !inline.markers.isHidden(34))
        let storage = inline.textStorage!
        #expect((storage.attribute(.inlineImage, at: 34, effectiveRange: nil) as? InlineImage)?.size == NSSize(width: 100, height: 40))
        #expect(storage.attribute(.blockDecoration, at: 6, effectiveRange: nil) == nil)
        layout(inline)
        // A rendered line's height ("after"; the caret's line is raw and shorter).
        let lineHeight = inline.layoutManager!.lineFragmentRect(forGlyphAt: inline.layoutManager!.glyphIndexForCharacter(at: 37), effectiveRange: nil).height
        let height = inline.layoutManager!.usedRect(for: inline.textContainer!).height
        // intro, the block's one blank line, after: three lines plus the picture and its gap.
        #expect(height > 2.5 * lineHeight + 40 && height < 3.5 * lineHeight + 40 + InlineStyle.imageGap, "height \(height) for lines of \(lineHeight)")
        // The caret inside the block reveals the source (the raw look, no decoration) and drops the picture.
        inline.setSelectedRange(NSRange(location: 17, length: 0))
        #expect(inline.revealed == NSRange(location: 6, length: 29))
        #expect(storage.attribute(.inlineImage, at: 34, effectiveRange: nil) == nil)
        #expect(storage.attribute(.blockDecoration, at: 6, effectiveRange: nil) == nil)
        #expect((storage.attribute(.font, at: 17, effectiveRange: nil) as? NSFont) == inline.style.regular)
        #expect((storage.attribute(.foregroundColor, at: 17, effectiveRange: nil) as? NSColor) == inline.style.code)
        #expect(inline.resolvedDiagrams.isEmpty && requests.count == 1)
        // Leaving brings the picture back from the cache.
        inline.setSelectedRange(NSRange(location: 37, length: 0))
        #expect(inline.resolvedDiagrams == [6] && requests.count == 1)
        #expect(storage.attribute(.inlineImage, at: 34, effectiveRange: nil) != nil)
    }

    @Test func drawsMathUnlessTheCaretIsOnItsLine() async throws {
        let image = NSImage(size: NSSize(width: 100, height: 40), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let picture = MathPicture(image: image, size: NSSize(width: 100, height: 40), baseline: 30)
        var requests: [MathRequest] = []
        let inline = ThemedTextView.standalone()
        inline.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        inline.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        inline.presentation = .inline
        inline.mathRenderer = { request, completion in
            requests.append(request)
            DispatchQueue.main.async { completion(picture) }
        }
        // "intro\n" 0–5, "Say $x^2$ now\n" 6–19 (token 10–14), "$$\n" 20–22, "y\n" 23–24, "$$" 25–26, "\n" 27, "after" 28–32.
        inline.replaceText(with: "intro\nSay $x^2$ now\n$$\ny\n$$\nafter")
        inline.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(inline.resolvedMath.isEmpty)
        #expect(requests.map(\.tex) == ["x^2", "y"] && requests.map(\.display) == [false, true] && requests.first?.fontSize == inline.style.body.pointSize)
        try await Task.sleep(for: .milliseconds(200))
        #expect(inline.resolvedMath == [10: 10, 20: 25])
        #expect(inline.markers.isAnchor(10) && inline.markers.isHidden(11) && inline.markers.isHidden(14) && !inline.markers.isHidden(15))
        #expect(inline.markers.isHidden(20) && inline.markers.isHidden(23) && !inline.markers.isHidden(25) && inline.markers.isHidden(26) && !inline.markers.isHidden(27))
        let storage = inline.textStorage!
        #expect((storage.attribute(.mathPicture, at: 10, effectiveRange: nil) as? MathPicture)?.size == NSSize(width: 100, height: 40))
        #expect((storage.attribute(.paragraphStyle, at: 25, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .center)
        #expect(storage.attribute(.blockDecoration, at: 23, effectiveRange: nil) == nil)
        layout(inline)
        let layoutManager = inline.layoutManager!
        let anchor = layoutManager.glyphIndexForCharacter(at: 10)
        #expect(layoutManager.propertyForGlyph(at: anchor) == .controlCharacter)
        let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: anchor, length: 1), in: inline.textContainer!)
        let plain = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
        // The formula's line grows to hold 30 pt above the baseline and 10 below, plus a small gap.
        #expect(box.width == 100 && box.height >= 40 && box.height < 40 + plain, "box \(box) for lines of \(plain)")
        let block = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 25), effectiveRange: nil)
        #expect(block.height >= 40 && block.height < 40 + plain, "block line \(block)")
        let height = layoutManager.usedRect(for: inline.textContainer!).height
        #expect(height >= 2 * plain + 80 && height < 4 * plain + 80, "height \(height)")
        // The caret on the formula's line shows its TeX with the dollars hidden and no picture.
        inline.setSelectedRange(NSRange(location: 8, length: 0))
        #expect(inline.resolvedMath == [20: 25] && !inline.markers.isAnchor(10) && inline.markers.isHidden(10) && !inline.markers.isHidden(11))
        #expect(storage.attribute(.mathPicture, at: 10, effectiveRange: nil) == nil)
        // Inside the block the whole block is source again (the raw look), and the other formula a picture.
        inline.setSelectedRange(NSRange(location: 23, length: 0))
        #expect(inline.revealed == NSRange(location: 20, length: 8) && inline.resolvedMath == [10: 10])
        #expect(storage.attribute(.blockDecoration, at: 23, effectiveRange: nil) == nil)
        #expect((storage.attribute(.font, at: 23, effectiveRange: nil) as? NSFont) == inline.style.regular)
        #expect(storage.attribute(.mathPicture, at: 25, effectiveRange: nil) == nil)
        // Leaving brings both back from the cache.
        inline.setSelectedRange(NSRange(location: 30, length: 0))
        #expect(inline.resolvedMath == [10: 10, 20: 25] && requests.count == 2)
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
        #expect((inline.textStorage!.attribute(.paragraphStyle, at: 15, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing == 0)
    }

    /// An image that is not next to the document is found in the attachments folder once the search is on.
    @Test func findsImagesInTheAttachmentsFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-inline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        let picture = NSImage(size: NSSize(width: 30, height: 10), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let png = NSBitmapImageRep(data: picture.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: directory.appendingPathComponent("attachments/file.png"))
        let inline = ThemedTextView.standalone()
        inline.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        inline.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        inline.baseURL = directory
        inline.presentation = .inline
        inline.replaceText(with: "![a](file.png)\nend")
        inline.setSelectedRange(NSRange(location: 17, length: 0))
        layout(inline)
        #expect((inline.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing == 0)
        inline.attachmentSearch = AttachmentSearch(searchesParents: false)
        layout(inline)
        #expect(inline.markers.isHidden(0))
        #expect((inline.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing == 18)
        inline.attachmentSearch = .direct
        layout(inline)
        #expect((inline.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing == 0)
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
        // The pipes after column 0 line up across rows, padded in points behind the shorter cell.
        #expect(abs(x(4) - x(29)) < 1, "\(x(4)) vs \(x(29))")
        let space = InlineStyle.width(of: " ", in: inline.style.body)
        #expect(x(29) > x(28) && x(4) > x(3) + 2 * space)
        // The delimiter row is hidden whole: only the container's padding remains.
        #expect(width(inline, line: 1) <= 2 * inline.textContainer!.lineFragmentPadding + 0.5)
    }

    @Test func plainClickOnALinkPlacesTheCaret() {
        let inline = editor("[text](https://example.com) after", presentation: .inline, caret: 30)
        inline.clicked(onLink: "https://example.com", at: 3)
        #expect(inline.selectedRange() == NSRange(location: 3, length: 0))
        #expect(inline.revealed == NSRange(location: 0, length: 33))
    }
}
