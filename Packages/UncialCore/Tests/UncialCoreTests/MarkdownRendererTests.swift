import Foundation
import Testing
@testable import UncialCore

@Suite struct MarkdownRendererTests {
    let renderer = MarkdownRenderer()

    @Test func rendersGitHubExtensions() {
        let markdown = """
        | a | b |
        |---|---|
        | 1 | 2 |

        - [x] done
        - [ ] todo

        ~~gone~~ see www.example.com
        """
        let html = renderer.renderBody(markdown)
        #expect(html.contains("<table>"))
        #expect(html.contains("<input type=\"checkbox\" checked=\"\" disabled=\"\" />"))
        #expect(html.contains("<del>gone</del>"))
        #expect(html.contains("<a href=\"http://www.example.com\">www.example.com</a>"))
    }

    @Test func rendersCalloutsWithLineLabels() {
        let html = renderer.renderBody("> [!tip] Hi\n> body\n\n> [!note]\n> only", sourcePositions: true)
        #expect(html.contains("<div class=\"callout\" data-callout=\"tip\" data-line=\"1\" data-sourcepos=\"1:1-2:6\">"))
        #expect(html.contains("<span class=\"callout-title-text\">Hi</span>"))
        #expect(html.contains("<p data-line=\"2\" data-sourcepos=\"2:1-2:6\">body</p>"))
        #expect(html.contains("<div class=\"callout\" data-callout=\"note\" data-line=\"4\" data-sourcepos=\"4:1-5:6\">"))
        #expect(html.contains("<span class=\"callout-title-text\">Note</span>"))
        #expect(html.contains("<p data-line=\"5\" data-sourcepos=\"5:1-5:6\">only</p>"))
        #expect(!html.contains("<blockquote"))
        #expect(renderer.renderBody("> plain").contains("<blockquote>"))
    }

    @Test func filtersDangerousRawHTMLButKeepsSafeHTML() {
        let html = renderer.renderBody("<script>alert(1)</script>\n\n<details><summary>More</summary>Body</details>")
        #expect(html.contains("&lt;script>"))
        #expect(!html.contains("<script>"))
        #expect(html.contains("<details><summary>More</summary>Body</details>"))
    }

    @Test func emptyInputProducesEmptyBody() {
        #expect(renderer.renderBody("") == "")
    }

    @Test func rendersFootnotesWithClosedBackref() {
        let html = renderer.renderBody("Note[^1]\n\n[^1]: Footnote text\n")
        #expect(html.contains("<section class=\"footnotes\""))
        #expect(html.contains("aria-label=\"Back to reference 1\">↩</a>"))
    }

    @Test func rendersFrontMatterAsBlock() {
        let html = renderer.renderBody("---\ntitle: Hi\n---\n# Body")
        #expect(html.hasPrefix("<pre class=\"front-matter\">title: Hi</pre>"))
        #expect(html.contains("<h1 id=\"body\">Body</h1>"))
    }

    @Test func rendersHeadingWithAnchor() {
        #expect(renderer.renderBody("# Hello World").contains("<h1 id=\"hello-world\">Hello World</h1>"))
    }

    @Test func documentWrapsBodyWithStyleAndTitle() {
        let html = renderer.renderDocument("# T", title: "A <B> & C.md")
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<meta name=\"color-scheme\" content=\"light dark\">"))
        #expect(html.contains("<title>A &lt;B&gt; &amp; C.md</title>"))
        #expect(html.contains("<style>"))
        #expect(html.contains("prefers-color-scheme: dark"))
        #expect(html.contains("<article class=\"markdown-body\">\n<h1 id=\"t\">T</h1>"))
    }

    @Test func documentInlinesImagesRelativeToBaseURL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-doc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x47, 0x49, 0x46]).write(to: directory.appendingPathComponent("a.gif"))
        let html = renderer.renderDocument("![a](a.gif)", title: "t", baseURL: directory.appendingPathComponent("doc.md"))
        #expect(html.contains("<img src=\"data:image/gif;base64,R0lG\" alt=\"a\" />"))
    }

    @Test func bodyInlinesImagesWhenGivenBaseURL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-body-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x47, 0x49, 0x46]).write(to: directory.appendingPathComponent("a.gif"))
        let body = renderer.renderBody("![a](a.gif)", baseURL: directory.appendingPathComponent("doc.md"))
        #expect(body.contains("<img src=\"data:image/gif;base64,R0lG\" alt=\"a\" />"))
        #expect(renderer.renderBody("![a](a.gif)").contains("<img src=\"a.gif\""))
    }

    /// Blocking web references costs nothing extra for local images: it runs before they become
    /// megabytes of base64, which it used to scan on every render (0.4 s for five photos).
    @Test func blockingTheWebSkipsInlinedImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-inline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var generator = SystemRandomNumberGenerator()
        try Data((0..<(6 << 20)).map { _ in UInt8.random(in: 0...255, using: &generator) }).write(to: directory.appendingPathComponent("big.png"))
        let document = directory.appendingPathComponent("doc.md")
        let markdown = "![big](big.png)\n\n![web](https://example.com/a.png)\n"
        let clock = ContinuousClock()
        func fastest(remoteContent: Bool) -> Duration {
            (0..<3).map { _ in clock.measure { _ = renderer.renderBody(markdown, baseURL: document, remoteContent: remoteContent) } }.min()!
        }
        _ = fastest(remoteContent: true)
        let open = fastest(remoteContent: true)
        let blocked = fastest(remoteContent: false)
        #expect(blocked < open * 2 + .milliseconds(20), "blocked \(blocked), open \(open)")
        let html = renderer.renderBody(markdown, baseURL: document, remoteContent: false)
        #expect(html.contains("<img src=\"data:image/png;base64,"))
        #expect(html.contains("data-blocked-src=\"https://example.com/a.png\""))
    }

    /// A pasted file whose name holds ":" (a "/" in Finder) is linked with it encoded, and the page finds it.
    @Test func inlinesImagesWhoseNamesHoldAColon() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-colon-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("a:b.gif")
        try Data([0x47, 0x49, 0x46]).write(to: image)
        let markdown = AttachmentImporter.markdown(for: image, relativeTo: directory)
        #expect(markdown == "![a:b](a%3Ab.gif)")
        #expect(renderer.renderBody(markdown, baseURL: directory.appendingPathComponent("doc.md")).contains("src=\"data:image/gif;base64,R0lG\""))
    }

    @Test func bodyAndDocumentFindImagesThroughTheAttachmentSearch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-attach-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        try Data([0x47, 0x49, 0x46]).write(to: directory.appendingPathComponent("attachments/a.gif"))
        let document = directory.appendingPathComponent("doc.md")
        #expect(renderer.renderBody("![a](a.gif)", baseURL: document).contains("<img src=\"a.gif\""))
        #expect(renderer.renderBody("![a](a.gif)", baseURL: document, attachments: AttachmentSearch()).contains("<img src=\"data:image/gif;base64,R0lG\""))
        #expect(renderer.renderDocument("![a](a.gif)", title: "t", baseURL: document, attachments: AttachmentSearch()).contains("<img src=\"data:image/gif;base64,R0lG\""))
    }

    @Test func documentUsesRequestedTheme() {
        let html = renderer.renderDocument("# T", title: "t", theme: .github)
        #expect(html.contains("data-theme=\"github\""))
        #expect(html.contains("#0d1117"))
        #expect(renderer.renderDocument("# T", title: "t").contains("data-theme=\"macos\""))
    }

    @Test func sourcePositionsAreOptInAndShiftedPastFrontMatter() {
        #expect(!renderer.renderBody("# T").contains("data-sourcepos"))
        #expect(renderer.renderBody("# T", sourcePositions: true).contains("<h1 id=\"t\" data-line=\"1\" data-sourcepos=\"1:1-1:3\">"))
        let html = renderer.renderBody("---\na: 1\n---\n# T\n\npara", sourcePositions: true)
        #expect(html.contains("data-sourcepos=\"4:1-4:3\""))
        #expect(html.contains("<p data-line=\"6\" data-sourcepos=\"6:1-6:4\">para</p>"))
        #expect(html.hasPrefix("<pre class=\"front-matter\">"))
    }

    @Test func sourcePositionsBringLineLabels() {
        let html = renderer.renderBody("# T\n\ntext", sourcePositions: true)
        #expect(html.contains("data-line=\"1\""))
        #expect(html.contains("<p data-line=\"3\" data-sourcepos=\"3:1-3:4\">text</p>"))
        #expect(!renderer.renderBody("# T\n\ntext").contains("data-line"))
    }

    /// The TeX of every formula on the page, as KaTeX received it (its annotation).
    private func tex(_ markdown: String) -> [String] {
        let html = renderer.renderBody(markdown) as NSString
        let annotation = try! NSRegularExpression(pattern: #"<annotation encoding="application/x-tex">([\s\S]*?)</annotation>"#)
        return annotation.matches(in: html as String, range: NSRange(location: 0, length: html.length)).map {
            html.substring(with: $0.range(at: 1))
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Math is taken from the source before cmark reads it: backslash escapes, `*` and `_` inside
    /// `$…$` and `$$…$$` reach KaTeX as written, as Live Preview already passes them.
    @Test func mathKeepsItsTeXThroughMarkdown() {
        #expect(tex("$$\n\\int_0^1 x^2 \\, dx = \\frac{1}{3}\n$$") == ["\\int_0^1 x^2 \\, dx = \\frac{1}{3}"])
        #expect(tex("$\\{x \\mid x > 0\\}$") == ["\\{x \\mid x > 0\\}"])
        #expect(tex("$\\|v\\|$") == ["\\|v\\|"])
        #expect(tex("$50\\% + x$") == ["50\\% + x"])
        #expect(tex("$$\n\\begin{aligned}\na &= b \\\\\nc &= d\n\\end{aligned}\n$$") == ["\\begin{aligned}\na &= b \\\\\nc &= d\n\\end{aligned}"])
        #expect(tex("$a*b*c$") == ["a*b*c"])
        #expect(tex("$x^*$ and $y^*$") == ["x^*", "y^*"])
        #expect(tex("$\\mathbf{x}_{i} + \\mathbf{y}_{j}$") == ["\\mathbf{x}_{i} + \\mathbf{y}_{j}"])
        #expect(tex("> quoted $a\\,b$") == ["a\\,b"])
        #expect(tex("> $$\n> a \\\\ b\n> $$") == ["a \\\\ b"])
        #expect(tex("- item\n\n  $$\n  a \\\\ b\n  $$") == ["a \\\\ b"])
        #expect(!renderer.renderBody("$x^*$ and $y^*$").contains("<em>"))
    }

    /// Escaped dollars, code spans, fenced and indented code keep their dollars as text.
    @Test func mathStaysLiteralWhereMarkdownSaysSo() {
        let html = renderer.renderBody("Costs \\$5 and \\$6.\n\n`$x$` and\n\n```\n$y$\n```\n\n    $z$")
        #expect(!html.contains("<math"))
        #expect(html.contains("Costs $5 and $6."))
        #expect(html.contains("<code>$x$</code>"))
        #expect(html.contains("$y$"))
        #expect(html.contains("$z$"))
    }

    /// Taking math out first changes neither source lines (scroll sync) nor heading anchors.
    @Test func mathKeepsLinesAndHeadingAnchors() {
        let html = renderer.renderBody("# The $x$ value\n\n$$\na \\\\\nb\n$$\n\nafter", sourcePositions: true)
        #expect(html.contains("id=\"the-x-value\""))
        #expect(html.contains("<p data-line=\"8\" data-sourcepos=\"8:1-8:5\">after</p>"))
    }
}
