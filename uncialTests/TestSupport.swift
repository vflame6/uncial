import AppKit
import WebKit
@testable import Uncial

/// A folder of its own in the temporary directory, deleted with the value. A suite that works with
/// files keeps one as a stored property: every test gets a fresh folder and leaves nothing behind.
final class TemporaryDirectory: Sendable {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// `path` inside the folder; nothing is created.
    func url(_ path: String, isDirectory: Bool = false) -> URL {
        url.appendingPathComponent(path, isDirectory: isDirectory)
    }

    /// Creates the folder at `path` and the folders on the way.
    @discardableResult
    func folder(_ path: String) throws -> URL {
        let folder = url(path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes `contents` to the file at `path`, creating the folders on the way.
    @discardableResult
    func file(_ path: String, _ contents: Data) throws -> URL {
        let file = url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file)
        return file
    }

    @discardableResult
    func file(_ path: String, _ contents: String = "") throws -> URL {
        try file(path, Data(contents.utf8))
    }
}

/// A standalone editor on `text`, `width` × `height` points, set up by `configure` before the text goes
/// in (loaders, renderers and the base URL must be there for the first pass), the caret at `caret` and
/// its layout done. The text container is `width` wide unless `tracksWidth`, which leaves it following
/// the view and its insets, as in the app.
@MainActor
func editor(_ text: String, presentation: EditorPresentation = .source, caret: Int = 0, width: CGFloat = 400, height: CGFloat = 200,
            tracksWidth: Bool = false, configure: (ThemedTextView) -> Void = { _ in }) -> ThemedTextView {
    let view = ThemedTextView.standalone()
    view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    if !tracksWidth {
        view.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    }
    view.presentation = presentation
    configure(view)
    view.replaceText(with: text)
    view.setSelectedRange(NSRange(location: caret, length: 0))
    view.layoutManager?.ensureLayout(for: view.textContainer!)
    return view
}

/// A `width` × `height` RGBA bitmap at one pixel per point, filled with `background`, that `draw` paints
/// into as the current context; `flipped` puts the origin at the top left, where TextKit has it.
@MainActor
func bitmap(width: Int, height: Int, background: NSColor = .white, flipped: Bool = true, _ draw: (NSGraphicsContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    background.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    if flipped {
        context.cgContext.translateBy(x: 0, y: CGFloat(height))
        context.cgContext.scaleBy(x: 1, y: -1)
    }
    draw(context)
    return rep
}

extension NSImage {
    /// A picture of nothing but `color`.
    static func filled(with color: NSColor, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }
}

/// Loads `html` into a 400-point WebKit view in a borderless window that is never shown, in
/// `appearance` when given, waits for the page, hands the view to `body` and closes the window.
@MainActor
func withWebPage<T>(_ html: String, appearance: NSAppearance.Name? = nil, _ body: (WKWebView) async throws -> T) async throws -> T {
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = webView
    defer { window.close() }
    if let appearance {
        webView.appearance = NSAppearance(named: appearance)
    }
    webView.loadHTMLString(html, baseURL: nil)
    for _ in 0..<100 where webView.isLoading || webView.estimatedProgress < 1 {
        try await Task.sleep(for: .milliseconds(50))
    }
    return try await body(webView)
}

/// Waits until `condition` holds, `seconds` at most: for what arrives in another turn of the main actor.
/// Suites share that actor, so a fixed pause ends first when other tests are busy on it.
@MainActor
func eventually(within seconds: Double = 3, _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// The editor as the app builds it (`MarkdownTextView.makeScrollView`), `width` × `height` points in a
/// window that is never shown, restyled after every edit as the SwiftUI coordinator does. `configure`
/// runs before the text goes in (loaders, renderers, the base URL). Close it when done.
@MainActor
final class EditorWindow: NSObject, NSTextViewDelegate {
    let window: NSWindow
    let scrollView: NSScrollView
    let textView: ThemedTextView

    init(_ text: String, presentation: EditorPresentation = .inline, width: CGFloat = 800, height: CGFloat = 600,
         configure: (ThemedTextView) -> Void = { _ in }) {
        scrollView = MarkdownTextView.makeScrollView()
        textView = scrollView.documentView as! ThemedTextView
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        super.init()
        window.contentView = scrollView
        window.layoutIfNeeded()
        textView.delegate = self
        textView.presentation = presentation
        configure(textView)
        textView.replaceText(with: text)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    func textDidChange(_ notification: Notification) {
        textView.rehighlight()
    }

    func close() {
        window.close()
    }

    /// Where the visible part of the text starts, in the text view's coordinates.
    var scrollOffset: CGFloat { scrollView.contentView.bounds.origin.y }

    /// Puts the caret at `location` and scrolls it into view.
    func moveCaret(to location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(NSRange(location: location, length: 0))
    }

    /// The top of the line fragment holding the character at `location`, from the top of the visible part.
    func visibleTop(ofCharacterAt location: Int) -> CGFloat {
        let layoutManager = textView.layoutManager!
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: location), effectiveRange: nil)
        return fragment.minY + textView.textContainerOrigin.y - scrollOffset
    }

    /// What the layout shows, one entry per line on screen: where the line is, the characters it holds,
    /// which of them are hidden or stand for a picture, and the glyphs they are drawn with. Two layouts
    /// of a text that agree on this look the same.
    func layoutSnapshot() -> [String] {
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        func number(_ value: CGFloat) -> String { String(format: "%.2f", value) }
        var lines: [String] = []
        var glyph = 0
        while glyph < layoutManager.numberOfGlyphs {
            var glyphs = NSRange()
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &glyphs)
            guard glyphs.length > 0 else { break }
            let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            var hidden: [Int] = []
            var boxes: [Int] = []
            var drawn: [CGGlyph] = []
            var shapes = [CGGlyph](repeating: 0, count: glyphs.length)
            var properties = [NSLayoutManager.GlyphProperty](repeating: [], count: glyphs.length)
            var indexes = [Int](repeating: 0, count: glyphs.length)
            layoutManager.getGlyphs(in: glyphs, glyphs: &shapes, properties: &properties, characterIndexes: &indexes, bidiLevels: nil)
            for index in 0..<glyphs.length {
                if properties[index].contains(.null) {
                    hidden.append(indexes[index])
                } else if properties[index].contains(.controlCharacter) {
                    boxes.append(indexes[index])
                } else {
                    drawn.append(shapes[index])
                }
            }
            lines.append("y \(number(rect.minY)) h \(number(rect.height)) used \(number(used.minX))+\(number(used.width)) at \(number(used.minY)) "
                + "characters \(characters.location)+\(characters.length) hidden \(hidden) boxes \(boxes) glyphs \(drawn.count):\(drawn.reduce(UInt64(17)) { ($0 &* 31) &+ UInt64($1) })")
            glyph = NSMaxRange(glyphs)
        }
        lines.append("extra \(number(layoutManager.extraLineFragmentRect.minY)) \(number(layoutManager.extraLineFragmentRect.height))")
        return lines
    }

    /// `layoutSnapshot()` after every glyph and line is made again: what the layout must be at any time.
    func layoutSnapshotMadeAgain() -> [String] {
        let layoutManager = textView.layoutManager!
        let whole = NSRange(location: 0, length: textView.textStorage!.length)
        layoutManager.invalidateGlyphs(forCharacterRange: whole, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: whole, actualCharacterRange: nil)
        return layoutSnapshot()
    }

    /// The text's height when all of it is laid out from nothing: what the height must be at any time.
    func heightLaidOutAgain() -> CGFloat {
        let layoutManager = textView.layoutManager!
        layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textView.textStorage!.length), actualCharacterRange: nil)
        layoutManager.ensureLayout(for: textView.textContainer!)
        return layoutManager.usedRect(for: textView.textContainer!).height
    }
}

/// Every stretch of text a storage reports as edited: what its layout managers lay out again.
final class StorageEdits: NSObject, NSTextStorageDelegate {
    private(set) var ranges: [NSRange] = []

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        ranges.append(editedRange)
    }

    /// The edits `body` makes to `storage`.
    @MainActor
    static func during(_ storage: NSTextStorage, _ body: () -> Void) -> [NSRange] {
        let edits = StorageEdits()
        let previous = storage.delegate
        storage.delegate = edits
        defer { storage.delegate = previous }
        body()
        return edits.ranges
    }
}
