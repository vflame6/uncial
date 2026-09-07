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
}
