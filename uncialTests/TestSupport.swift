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
