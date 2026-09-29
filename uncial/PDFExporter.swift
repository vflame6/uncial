import AppKit
import CoreText
import PDFKit
import WebKit

/// Why an export wrote no file.
enum ExportError: LocalizedError {
    case printFailed
    case unreadablePrint
    case unwritablePDF

    var errorDescription: String? {
        switch self {
        case .printFailed: "WebKit could not print the page."
        case .unreadablePrint: "The printed pages could not be read back."
        case .unwritablePDF: "The PDF could not be written."
        }
    }
}

/// Prints a rendered page (`MarkdownRenderer.renderExport`, fixed light) to a paginated PDF on the
/// default paper, each page's number in the middle of its bottom margin. WebKit lays the page out for
/// paper in a web view whose window is never shown. Probed 2026-09-29: its print operation writes the
/// PDF with no panel through `runModal(for:…)`, while `run()` never returns; text stays selectable and
/// links live; backgrounds print only with `shouldPrintBackgrounds` (without it WebKit also darkens
/// light text). Content JavaScript is off, the page's own load is the only navigation, and with remote
/// content off `RemoteContentBlocker`'s rules keep it off the web. No base URL: WebKit would write
/// relative links into the PDF as `file:` paths of this Mac. One exporter prints one page.
final class PDFExporter: NSObject, WKNavigationDelegate {
    /// Every page margin, 0.75 in.
    nonisolated static let margin: CGFloat = 54

    /// Run before printing (app-authored: `evaluateJavaScript` works with content JavaScript off). Opens
    /// every `<details>`, since a folded callout would hide its text on paper for good, and wraps each
    /// heading followed by a block WebKit does not split in `div.print-keep`, which the print rules keep
    /// on one page: WebKit ignores `break-after: avoid`, so a heading could end a page and its code,
    /// table, picture or callout start the next. Answers the number of headings kept.
    static let preparation = """
    (() => {
      for (const details of document.querySelectorAll('details')) details.open = true;
      const unsplittable = 'pre, table, figure, .callout, p.math, p:has(> img:only-child)';
      let kept = 0;
      for (const heading of document.querySelectorAll('.markdown-body :is(h1, h2, h3, h4, h5, h6)')) {
        const next = heading.nextElementSibling;
        if (!next || !next.matches(unsplittable)) continue;
        const keep = document.createElement('div');
        keep.className = 'print-keep';
        heading.before(keep);
        keep.append(heading, next);
        kept += 1;
      }
      return kept;
    })()
    """

    private let loadBudget: Duration
    private let webView: WKWebView
    private let window: NSWindow
    private var navigation: WKNavigation?
    private var hasNavigated = false
    private var processTerminated = false
    private var loading: CheckedContinuation<Void, Never>?
    private var printing: CheckedContinuation<Bool, Never>?

    /// `loadBudget`: how long the page may take to load (remote pictures) before it prints with what it has.
    init(loadBudget: Duration = .seconds(20)) {
        self.loadBudget = loadBudget
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.shouldPrintBackgrounds = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000), configuration: configuration)
        window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.contentView = webView
        webView.appearance = NSAppearance(named: .aqua)
        webView.navigationDelegate = self
    }

    /// Writes `html` to `url` as a numbered PDF whose document title is `title`, replacing a file there.
    func write(html: String, title: String, remoteContent: Bool, to url: URL) async throws {
        defer { window.close() }
        if !remoteContent, let rules = await RemoteContentBlocker.shared.ruleList() {
            webView.configuration.userContentController.add(rules)
        }
        await load(html)
        guard !processTerminated else { throw ExportError.printFailed }
        await evaluate(Self.preparation)
        let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: url.deletingLastPathComponent(), create: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let printed = folder.appendingPathComponent("printed.pdf")
        guard await printPages(to: printed, title: title), !processTerminated else { throw ExportError.printFailed }
        let numbered = folder.appendingPathComponent("numbered.pdf")
        try await Task.detached(priority: .userInitiated) {
            try PageNumbers.write(from: printed, to: numbered, title: title)
        }.value
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: numbered)
        } else {
            try FileManager.default.moveItem(at: numbered, to: url)
        }
    }

    /// Loads the page and returns once it has (pictures included) or once `loadBudget` is spent; then
    /// loading stops and the page prints with what arrived.
    private func load(_ html: String) async {
        let budget = loadBudget
        await withCheckedContinuation { continuation in
            loading = continuation
            navigation = webView.loadHTMLString(html, baseURL: nil)
            Task { [weak self] in
                try? await Task.sleep(for: budget)
                guard let self, self.loading != nil else { return }
                self.webView.stopLoading()
                self.finishLoading()
            }
        }
    }

    private func finishLoading() {
        loading?.resume()
        loading = nil
    }

    /// Runs an app-authored script, callback form: the async one traps on a script that yields `undefined`.
    private func evaluate(_ script: String) async {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { _, _ in continuation.resume() }
        }
    }

    private func printPages(to url: URL, title: String) async -> Bool {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = Self.margin
        info.bottomMargin = Self.margin
        info.leftMargin = Self.margin
        info.rightMargin = Self.margin
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.jobTitle = title
        // The operation's view takes the web view's size, as in the probe.
        operation.view?.frame = webView.bounds
        return await withCheckedContinuation { continuation in
            printing = continuation
            operation.runModal(for: window, delegate: self, didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        printing?.resume(returning: success)
        printing = nil
    }

    /// The page's own load is the one navigation: a refresh, or anything else the page starts, would
    /// replace it before it prints.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = !hasNavigated && navigationAction.targetFrame?.isMainFrame == true
        hasNavigated = true
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if navigation === self.navigation { finishLoading() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if navigation === self.navigation { finishLoading() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if navigation === self.navigation { finishLoading() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        processTerminated = true
        finishLoading()
        printing?.resume(returning: false)
        printing = nil
    }
}

/// Writes each page's number into a PDF, centered in the bottom margin: PDFKit draws every page through
/// `NumberedPDFPage` when it writes the document, so the number becomes part of the page (Apple's
/// watermark technique; probed 2026-09-29, text and link annotations stay). Also sets the document's
/// title and creator.
nonisolated enum PageNumbers {
    static func write(from source: URL, to destination: URL, title: String) throws {
        guard let document = PDFDocument(url: source) else { throw ExportError.unreadablePrint }
        let numbering = PageNumbering()
        document.delegate = numbering
        var attributes = document.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.titleAttribute] = title
        attributes[PDFDocumentAttribute.creatorAttribute] = "Uncial"
        document.documentAttributes = attributes
        let written = document.write(to: destination)
        withExtendedLifetime(numbering) {}
        guard written else { throw ExportError.unwritablePDF }
    }
}

/// Makes a document's pages `NumberedPDFPage`s (the delegate is asked before a page is first made).
nonisolated final class PageNumbering: NSObject, PDFDocumentDelegate {
    func classForPage() -> AnyClass { NumberedPDFPage.self }
}

/// A page that draws its number, 9 pt gray, centered 24 pt above the bottom edge (inside the 54 pt margin).
nonisolated final class NumberedPDFPage: PDFPage {
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        guard let document else { return }
        let font = CTFontCreateUIFontForLanguage(.system, 9, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 9, nil)
        let number = NSAttributedString(string: "\(document.index(for: self) + 1)", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.45, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(number)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let bounds = bounds(for: box)
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: bounds.midX - width / 2, y: bounds.minY + PDFExporter.margin / 2 - 3)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
