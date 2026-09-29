import AppKit
import PDFKit
import Testing
import UncialCore
import WebKit
@testable import Uncial

@MainActor
@Suite(.serialized) final class PDFExporterTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-pdf-\(UUID().uuidString)", isDirectory: true)

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A long note prints on several pages of the default paper, each numbered in its bottom margin,
    /// with its text selectable, its links live and its title and creator set.
    @Test func printsNumberedPagesWithTextAndLinks() async throws {
        let paragraphs = (1...80).map { "Paragraph \($0) runs long enough to fill a line and a half of a printed page, so the note needs several pages." }
        let markdown = "# Long note\n\nSee [the site](https://example.com/page).\n\n" + paragraphs.joined(separator: "\n\n")
        let html = MarkdownRenderer().renderExport(markdown, title: "Long note", remoteContent: false, appearance: .light)
        let url = folder.appendingPathComponent("long.pdf")
        try await PDFExporter().write(html: html, title: "Long note", remoteContent: false, to: url)

        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount > 1)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).size == NSPrintInfo.shared.paperSize)
        for index in 0..<document.pageCount {
            let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            #expect(text.hasSuffix("\(index + 1)"), "page \(index + 1) ends with “\(text.suffix(30))”")
        }
        #expect(document.string?.contains("Paragraph 80 runs long") == true)
        let links = (0..<document.pageCount).flatMap { document.page(at: $0)?.annotations ?? [] }
            .compactMap { $0.url ?? ($0.action as? PDFActionURL)?.url }
        #expect(links.contains(URL(string: "https://example.com/page")!))
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Long note")
        #expect(document.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String == "Uncial")
    }

    /// Before printing, folded callouts open, and a heading goes with the code block or picture after
    /// it, not with a paragraph.
    @Test func preparationKeepsHeadingsWithTheirBlocks() async throws {
        let body = """
        <h2>Code</h2><pre><code>let x = 1</code></pre>
        <h2>Text</h2><p>Words</p>
        <h2>Picture</h2><p><img src="data:image/gif;base64,R0lGODlhAQABAAAAACw="></p>
        <details class="callout" data-callout="note"><summary class="callout-title">Folded</summary><div class="callout-content"><p>Inside</p></div></details>
        """
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        defer { window.close() }
        webView.loadHTMLString(HTMLDocument.wrap(body: body, title: "t"), baseURL: nil)
        for _ in 0..<100 where webView.isLoading || webView.estimatedProgress < 1 {
            try await Task.sleep(for: .milliseconds(50))
        }
        let kept = try await webView.evaluateJavaScript(PDFExporter.preparation) as? Int
        #expect(kept == 2)
        let shape = try await webView.evaluateJavaScript("""
        [...document.querySelectorAll('.print-keep')].map(k => [...k.children].map(c => c.tagName).join('+')).join(',')
          + '|' + document.querySelector('details').open
        """) as? String
        #expect(shape == "H2+PRE,H2+P|true")
    }

    /// With remote content off the print view loads nothing from the web, even from a page nothing sanitized.
    @Test func staysOffTheWebWithRemoteContentOff() async throws {
        let listener = try LoopbackListener()
        await listener.start()
        defer { listener.stop() }
        let html = HTMLDocument.wrap(body: "<p>Words</p><img src=\"http://127.0.0.1:\(listener.port)/a.png\">", title: "t")
        try await PDFExporter(loadBudget: .seconds(2)).write(html: html, title: "t", remoteContent: false, to: folder.appendingPathComponent("off.pdf"))
        #expect(listener.connections == 0)
        try await PDFExporter(loadBudget: .seconds(2)).write(html: html, title: "t", remoteContent: true, to: folder.appendingPathComponent("on.pdf"))
        #expect(listener.connections > 0)
    }

    /// A picture that never arrives holds the print for the load budget only.
    @Test func aStalledPictureHoldsThePrintOnlyForTheBudget() async throws {
        let server = try LoopbackHTTPServer(routes: ["/slow.png": .stall(contentType: "image/png", bytes: Data())])
        await server.start()
        defer { server.stop() }
        let html = HTMLDocument.wrap(body: "<p>Still printed</p><img src=\"\(server.url("/slow.png").absoluteString)\">", title: "t")
        let url = folder.appendingPathComponent("stalled.pdf")
        let started = ContinuousClock.now
        try await PDFExporter(loadBudget: .seconds(1)).write(html: html, title: "t", remoteContent: true, to: url)
        #expect(ContinuousClock.now - started < .seconds(10))
        #expect(PDFDocument(url: url)?.string?.contains("Still printed") == true)
    }

    /// A refresh in the document cannot replace the page before it prints.
    @Test func aRefreshDoesNotReplaceThePage() async throws {
        let html = HTMLDocument.wrap(body: "<meta http-equiv=\"refresh\" content=\"0; url=https://example.com/\"><p>Original words</p>", title: "t")
        let url = folder.appendingPathComponent("refresh.pdf")
        try await PDFExporter(loadBudget: .seconds(2)).write(html: html, title: "t", remoteContent: true, to: url)
        #expect(PDFDocument(url: url)?.string?.contains("Original words") == true)
    }

    @Test func replacesAFileThatIsThere() async throws {
        let url = folder.appendingPathComponent("again.pdf")
        try Data("old".utf8).write(to: url)
        try await PDFExporter().write(html: HTMLDocument.wrap(body: "<p>New words</p>", title: "t"), title: "t", remoteContent: false, to: url)
        #expect(PDFDocument(url: url)?.string?.contains("New words") == true)
    }
}
